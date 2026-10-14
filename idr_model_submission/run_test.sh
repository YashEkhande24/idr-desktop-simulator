#!/usr/bin/env bash
# ==============================================================================
# IDR-NeuroSpeed-TCN : One-Click Verification Launcher (Linux / macOS)
# Smart India Hackathon (SIH 2026) Official Evaluation Script
# ==============================================================================
echo ""
echo "======================================================================"
echo "   Starting IDR-NeuroSpeed-TCN Model Verification Suite (SIH 2026)"
echo "======================================================================"
echo ""

python3 test.py --plot --export results.json

echo ""
echo "Test run complete. Benchmark plots saved to eval_plots/ and results.json."
