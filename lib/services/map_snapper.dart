import 'dart:math' as math;
import '../core/math_utils.dart';

/// Road branch polyline segment for 3D map matching from offline map database (e.g. OpenStreetMap).
class MapBranch {
  final String name;
  final List<Vec3> points;
  final bool isElevated;
  final bool isTunnel;
  final double speedLimitMps;
  final bool oneWay;
  final int lanes;

  const MapBranch({
    required this.name,
    required this.points,
    this.isElevated = false,
    this.isTunnel = false,
    this.speedLimitMps = 16.67, // ~60 km/h default
    this.oneWay = false,
    this.lanes = 2,
  });

  /// Lazily constructed C2-continuous cubic spline for smooth road curvature and tangent evaluation.
  CubicSpline3D? get spline => points.length >= 2 ? CubicSpline3D.fromPoints(points) : null;
}

/// Snapped map-matching result containing geometric projections, normal vectors, and confidence.
class MapSnapResult {
  final String branchName;
  final Vec3 snappedPoint;
  final Vec3 normal2D;
  final Vec3 tangent2D;
  final double crossTrackDistance; // signed meters: positive = right, negative = left
  final int segmentIndex;
  final double roadHeadingRad;
  final double confidence; // 0.0 .. 1.0 margin between top candidate branches
  final bool isElevated;
  final double curvature; // Menger curvature kappa (1/m)
  final int lanes;

  const MapSnapResult({
    required this.branchName,
    required this.snappedPoint,
    required this.normal2D,
    required this.tangent2D,
    required this.crossTrackDistance,
    required this.segmentIndex,
    required this.roadHeadingRad,
    this.confidence = 1.0,
    this.isElevated = false,
    this.curvature = 0.0,
    this.lanes = 2,
  });
}

/// Module 5: Smart 3D Map-Matching Filter (Whitepaper Section 7).
///
/// Implements spatial constraints using an offline road database (e.g., OpenStreetMap):
/// 1. Clamped Orthogonal Vector Projection (Eqns 30-32):
///    t = ((P - A) . (B - A)) / ||B - A||^2
///    t_clamped = max(0, min(1, t))
///    P_snap = A + t_clamped * (B - A)
///
/// 2. Multi-Tier 3D Elevation & Heading Disambiguation (Eqn 33):
///    J_k = d_lat + beta * |z_P - z_road| + gamma * (1 - |cos(psi_P - psi_road)|)
///    Disambiguates multi-level elevated flyovers from at-grade service roads beneath them.
///
/// 3. HDOP-Scheduled Constraint Variance (Continuous Sigmoidal Snapping):
///    Tighter road constraint (sigma ~ 1.0m) when GNSS is lost or in a tunnel (high HDOP),
///    gentle constraint (sigma ~ 4.5m) under clear sky to allow lane changes and overtaking.
class MapSnapper {
  final List<MapBranch> branches;
  final double beta; // Vertical elevation weight factor (Eqn 33)
  final double headingWeight; // Heading alignment weight factor
  final double maxLateralSnapM; // Maximum search corridor radius in meters
  final double sigmaLateralBase; // Nominal lateral constraint standard deviation
  final double hdopGain; // Sigmoid slope for HDOP scaling
  final double hdopCentre; // Sigmoid inflection point (e.g. 3.5)

  MapSnapResult? _lastResult;
  MapSnapResult? get lastResult => _lastResult;

  // Hidden Markov Model (HMM) Viterbi Trellis State
  String? _trellisBranchName;
  Vec3? _trellisSnappedPos;
  Vec3? _prevP;

  void reset() {
    _lastResult = null;
    _trellisBranchName = null;
    _trellisSnappedPos = null;
    _prevP = null;
  }

  MapSnapper({
    required this.branches,
    this.beta = 0.55,
    this.headingWeight = 6.0,
    this.maxLateralSnapM = 45.0,
    this.sigmaLateralBase = 1.1,
    this.hdopGain = 1.2,
    this.hdopCentre = 3.5,
  });

  /// Snaps unconstrained 3D position P to nearest road segment conditioned on elevation, heading, and speed reachability.
  /// Uses Hidden Markov Model (HMM) Viterbi Trellis path decoding:
  /// Evaluates emission probabilities (orthogonal distance) and transition probabilities (routing distance vs INS displacement).
  /// [vTcn]: Optional forward speed from TCN Speed Engine for speed-adaptive search corridor.
  /// [tcnVariance]: Optional predictive variance from TCN Speed Engine.
  MapSnapResult? snapWithHeading(
    Vec3 P,
    double? headingRad, {
    double? hdop,
    double? vTcn,
    double? tcnVariance,
  }) {
    if (branches.isEmpty) return null;

    // Speed-adaptive search corridor:
    // At low vehicle speeds (< 20 km/h), corridor contracts to prevent jumping into adjacent lanes or service roads.
    // At highway speeds, corridor expands smoothly up to maxLateralSnapM.
    final effectiveSnapM = vTcn != null
        ? MathUtils.clamp(vTcn * 1.5 + 3.0 * math.sqrt(tcnVariance ?? 0.16) + 12.0, 15.0, maxLateralSnapM)
        : maxLateralSnapM;

    MapSnapResult? bestResult;
    final scores = <double>[];
    double bestScore = double.infinity;

    for (final branch in branches) {
      final pts = branch.points;
      if (pts.length < 2) continue;

      for (int i = 0; i < pts.length - 1; i++) {
        final A = pts[i];
        final B = pts[i + 1];

        // Fast Axis-Aligned Bounding Box (AABB) rejection:
        // Skip segment if completely outside speed-adaptive lateral snap radius
        final minX = A.x < B.x ? A.x : B.x;
        final maxX = A.x > B.x ? A.x : B.x;
        if (P.x < minX - effectiveSnapM || P.x > maxX + effectiveSnapM) continue;

        final minY = A.y < B.y ? A.y : B.y;
        final maxY = A.y > B.y ? A.y : B.y;
        if (P.y < minY - effectiveSnapM || P.y > maxY + effectiveSnapM) continue;

        final abX = B.x - A.x;
        final abY = B.y - A.y;
        final abZ = B.z - A.z;
        final len2_2d = abX * abX + abY * abY;
        if (len2_2d < 1e-6) continue;

        // Whitepaper Eqn (30): Projection scalar t
        final paX = P.x - A.x;
        final paY = P.y - A.y;
        final t = (paX * abX + paY * abY) / len2_2d;

        // Whitepaper Eqn (31): t_clamped = max(0, min(1, t))
        final tClamped = MathUtils.clamp(t, 0.0, 1.0);

        // Whitepaper Eqn (32): P_snap = A + t_clamped * (B - A)
        final snapX = A.x + tClamped * abX;
        final snapY = A.y + tClamped * abY;
        final snapZ = A.z + tClamped * abZ;
        final snapPos = Vec3(snapX, snapY, snapZ);

        // Lateral distance in horizontal plane
        final dx = P.x - snapX;
        final dy = P.y - snapY;
        final lateralDist = math.sqrt(dx * dx + dy * dy);

        // 2D Unit Tangent & Normal with C1/C2 transition smoothing across node vertices
        final len2d = math.sqrt(len2_2d);
        var tangent2 = Vec3(abX / len2d, abY / len2d, 0.0);

        // Smooth transition when near vertices if adjacent segment exists in branch
        if (tClamped > 0.80 && i < pts.length - 2) {
          final nextB = pts[i + 2];
          final nextAbX = nextB.x - B.x;
          final nextAbY = nextB.y - B.y;
          final nextLen2d = math.sqrt(nextAbX * nextAbX + nextAbY * nextAbY);
          if (nextLen2d > 1e-4) {
            final nextTan = Vec3(nextAbX / nextLen2d, nextAbY / nextLen2d, 0.0);
            final u = (tClamped - 0.80) / 0.20;
            final wC1 = u * u * (3.0 - 2.0 * u); // Cubic Hermite smoothstep
            tangent2 = (tangent2 * (1.0 - wC1) + nextTan * wC1).normalized;
          }
        } else if (tClamped < 0.20 && i > 0) {
          final prevA = pts[i - 1];
          final prevAbX = A.x - prevA.x;
          final prevAbY = A.y - prevA.y;
          final prevLen2d = math.sqrt(prevAbX * prevAbX + prevAbY * prevAbY);
          if (prevLen2d > 1e-4) {
            final prevTan = Vec3(prevAbX / prevLen2d, prevAbY / prevLen2d, 0.0);
            final u = (0.20 - tClamped) / 0.20;
            final wC1 = u * u * (3.0 - 2.0 * u); // Cubic Hermite smoothstep
            tangent2 = (tangent2 * (1.0 - wC1) + prevTan * wC1).normalized;
          }
        }

        final normal2 = Vec3(-tangent2.y, tangent2.x, 0.0);
        final signedCrossTrack = dx * normal2.x + dy * normal2.y;
        final roadHeading = math.atan2(tangent2.y, tangent2.x);

        // 1. HMM Emission Cost: Log-likelihood of spatial orthogonal distance and elevation difference
        final altDiff = (P.z - snapZ).abs();
        double emissionCost = lateralDist + beta * altDiff;

        if (headingRad != null) {
          final headingVec = Vec3(math.cos(headingRad), math.sin(headingRad), 0.0);
          final dotHeading = (headingVec.x * tangent2.x + headingVec.y * tangent2.y).abs();
          emissionCost += headingWeight * (1.0 - dotHeading);
        }

        // 2. HMM Transition Cost: Log-likelihood of network route displacement vs INS displacement (Newson & Krumm)
        double transitionCost = 0.0;
        if (_trellisBranchName != null && _trellisSnappedPos != null && _prevP != null) {
          final dIns = (P - _prevP!).norm;
          final dRoute = (snapPos - _trellisSnappedPos!).norm;
          final diff = (dRoute - dIns).abs();
          final betaTrans = math.max(1.5, (vTcn ?? 10.0) * 0.4);
          transitionCost = diff / betaTrans;

          // Topological branch continuity penalty: prevents jumping to adjacent parallel service roads
          if (branch.name != _trellisBranchName) {
            transitionCost += 2.0;
          }
        } else if (_lastResult != null && branch.name != _lastResult!.branchName) {
          transitionCost += 1.5;
        }

        final score = emissionCost + transitionCost;
        scores.add(score);

        // Menger Curvature on 3 consecutive polyline points
        double kappa = 0.0;
        if (pts.length >= 3) {
          final nodeA = i > 0 ? pts[i - 1] : A;
          final nodeB = A;
          final nodeC = B;
          kappa = MathUtils.mengerCurvature(nodeA, nodeB, nodeC);
        }

        if (score < bestScore) {
          bestScore = score;
          bestResult = MapSnapResult(
            branchName: branch.name,
            snappedPoint: snapPos,
            normal2D: normal2,
            tangent2D: tangent2,
            crossTrackDistance: signedCrossTrack,
            segmentIndex: i,
            roadHeadingRad: roadHeading,
            isElevated: branch.isElevated,
            curvature: kappa,
            lanes: branch.lanes,
          );
        }
      }
    }

    if (bestResult == null || bestResult.crossTrackDistance.abs() > effectiveSnapM) {
      _lastResult = null;
      _trellisBranchName = null;
      _trellisSnappedPos = null;
      _prevP = null;
      return null;
    }

    // Confidence metric: normalized margin between best and second-best candidate branches
    double confidence = 1.0;
    if (scores.length > 1) {
      scores.sort();
      final gap = scores[1] - scores[0];
      confidence = MathUtils.clamp(gap / math.max(scores[1], 1e-6), 0.0, 1.0);
    }

    final finalResult = MapSnapResult(
      branchName: bestResult.branchName,
      snappedPoint: bestResult.snappedPoint,
      normal2D: bestResult.normal2D,
      tangent2D: bestResult.tangent2D,
      crossTrackDistance: bestResult.crossTrackDistance,
      segmentIndex: bestResult.segmentIndex,
      roadHeadingRad: bestResult.roadHeadingRad,
      confidence: confidence,
      isElevated: bestResult.isElevated,
      curvature: bestResult.curvature,
      lanes: bestResult.lanes,
    );

    // Update HMM Trellis state for next epoch
    _lastResult = finalResult;
    _trellisBranchName = finalResult.branchName;
    _trellisSnappedPos = finalResult.snappedPoint;
    _prevP = P;

    return finalResult;
  }

  /// Backward compatible 3D position snapping.
  MapSnapResult? snap(Vec3 P) {
    return snapWithHeading(P, null);
  }

  /// HDOP-scheduled constraint standard deviation.
  /// When GNSS HDOP surges in a tunnel or canyon, constraint tightens toward sigmaLateralBase.
  double lateralSigma(double hdop, [MapSnapResult? match]) {
    final z = hdopGain * (hdop - hdopCentre);
    final clampedZ = MathUtils.clamp(z, -20.0, 20.0);
    final lam = 1.0 / (1.0 + math.exp(-clampedZ));
    double sigma = sigmaLateralBase * (1.0 + 3.0 * (1.0 - lam));
    if (match != null) {
      sigma *= 1.0 + 2.0 * (1.0 - match.confidence);
    }
    return sigma;
  }

  /// Effective carriageway corridor deadband half-width (meters) based on lane count.
  /// Standard highway lane is 3.5m wide. Default: 1.75m (single lane half-width).
  double laneDeadband([MapSnapResult? match]) {
    final laneCount = match?.lanes ?? 2;
    return math.max(1.75, (laneCount * 3.5) / 2.0);
  }

  /// Factory providing standard SIH benchmark road network with multi-tier flyover and tunnel.
  static List<MapBranch> createDefaultBenchmarkBranches() {
    return [
      // 1. Main Expressway Section 0m -> 160m (Eastbound heading 0 rad)
      const MapBranch(
        name: 'NH-48 Main Expressway',
        points: [
          Vec3(0.0, 0.0, 0.0),
          Vec3(60.0, 0.0, 0.0),
          Vec3(120.0, 0.0, 0.0),
          Vec3(160.0, 0.0, 0.0),
        ],
        speedLimitMps: 16.67,
      ),

      // 2. Curved Highway Transition (90-degree turn toward North)
      const MapBranch(
        name: 'Interchange Curved Ramp',
        points: [
          Vec3(160.0, 0.0, 0.0),
          Vec3(210.0, 15.0, 0.0),
          Vec3(250.0, 50.0, 0.0),
          Vec3(275.0, 95.0, 0.0),
          Vec3(280.0, 140.0, 0.0),
        ],
        speedLimitMps: 14.0,
      ),

      // 3. Urban Corridor & Severe Pothole Zone (Northbound)
      const MapBranch(
        name: 'Urban Corridor (Rough Road Zone)',
        points: [
          Vec3(280.0, 140.0, 0.0),
          Vec3(280.0, 240.0, 0.0),
          Vec3(280.0, 350.0, 0.0),
        ],
        speedLimitMps: 12.5,
      ),

      // 4. Multi-Level Flyover Deck (Tier 2 Elevated Highway Climbing +18m)
      const MapBranch(
        name: 'Elevated Flyover Deck (Tier 2)',
        isElevated: true,
        points: [
          Vec3(280.0, 350.0, 0.0),
          Vec3(280.0, 420.0, 6.0),
          Vec3(280.0, 500.0, 14.0),
          Vec3(280.0, 600.0, 18.0),
        ],
        speedLimitMps: 18.0,
      ),

      // 5. Decoy At-Grade Service Road (Runs directly UNDER the flyover at z = 0.0m)
      // Disambiguated by elevation weighting beta so elevated cars do NOT snap to this!
      const MapBranch(
        name: 'At-Grade Service Road (Underpass)',
        isElevated: false,
        points: [
          Vec3(280.0, 350.0, 0.0),
          Vec3(280.0, 420.0, 0.0),
          Vec3(280.0, 500.0, 0.0),
          Vec3(280.0, 600.0, 0.0),
        ],
        speedLimitMps: 8.33, // 30 km/h service road
      ),

      // 6. Underground Highway Tunnel (GNSS-Denied 60s Outage Zone)
      const MapBranch(
        name: 'Underground Highway Tunnel',
        points: [
          Vec3(280.0, 600.0, 18.0),
          Vec3(280.0, 900.0, 18.0),
          Vec3(280.0, 1250.0, 18.0),
          Vec3(280.0, 1600.0, 18.0),
          Vec3(280.0, 1850.0, 18.0),
        ],
        speedLimitMps: 16.67,
      ),
    ];
  }
}

