"""
build_copyright_proposal.py
===========================
Generates the comprehensive, non-AI styled Technical Copyright Proposal & Specification Document:
1. e:\\inventor\\CopyRight Proposal.docx
2. e:\\inventor\\CopyRight Proposal.pdf
3. e:\\inventor\\COPYRIGHT_PROPOSAL.md
"""

import os
import sys
import subprocess
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

# Colors
NAVY = RGBColor(16, 44, 87)        # #102C57
DEEP_BLUE = RGBColor(28, 78, 137)  # #1C4E89
CYAN = RGBColor(0, 119, 182)       # #0077B6
DARK_GRAY = RGBColor(34, 34, 34)   # #222222
MUTED_GRAY = RGBColor(100, 100, 100)
WHITE = RGBColor(255, 255, 255)
GREEN = RGBColor(16, 124, 65)

def set_cell_background(cell, hex_color):
    shading_xml = f'<w:shd {nsdecls("w")} w:fill="{hex_color}"/>'
    cell._tc.get_or_add_tcPr().append(parse_xml(shading_xml))

def set_cell_borders(cell, top=None, bottom=None, left=None, right=None):
    tcPr = cell._tc.get_or_add_tcPr()
    tcBorders = OxmlElement('w:tcBorders')
    borders = {'top': top, 'bottom': bottom, 'left': left, 'right': right}
    for b_name, b_val in borders.items():
        if b_val:
            node = OxmlElement(f'w:{b_name}')
            node.set(qn('w:val'), b_val.get('val', 'single'))
            node.set(qn('w:sz'), str(b_val.get('sz', 4)))
            node.set(qn('w:space'), '0')
            node.set(qn('w:color'), b_val.get('color', 'auto'))
            tcBorders.append(node)
        else:
            node = OxmlElement(f'w:{b_name}')
            node.set(qn('w:val'), 'none')
            tcBorders.append(node)
    tcPr.append(tcBorders)

def add_callout(doc, text, title=None, border_color="102C57", bg_color="F4F7FB"):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    cell = tbl.cell(0, 0)
    cell.width = Inches(6.7)
    set_cell_background(cell, bg_color)
    set_cell_borders(cell, 
                     left={'val': 'single', 'sz': 24, 'color': border_color},
                     top={'val': 'none'}, right={'val': 'none'}, bottom={'val': 'none'})
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = 1.15
    if title:
        r_title = p.add_run(title + "\n")
        r_title.font.name = "Calibri"
        r_title.font.bold = True
        r_title.font.size = Pt(11)
        r_title.font.color.rgb = NAVY
    r_text = p.add_run(text)
    r_text.font.name = "Calibri"
    r_text.font.size = Pt(10)
    r_text.font.color.rgb = DARK_GRAY
    doc.add_paragraph()

def add_heading_1(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(18)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.bold = True
    r.font.size = Pt(13.5)
    r.font.color.rgb = NAVY
    return p

def add_heading_2(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.bold = True
    r.font.size = Pt(11.5)
    r.font.color.rgb = DEEP_BLUE
    return p

def add_body_p(doc, text, bold_prefix=None, space_after=4):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing = 1.15
    if bold_prefix:
        rb = p.add_run(bold_prefix)
        rb.font.name = "Calibri"
        rb.font.bold = True
        rb.font.size = Pt(10)
        rb.font.color.rgb = DARK_GRAY
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.size = Pt(10)
    r.font.color.rgb = DARK_GRAY
    return p

def add_bullet_p(doc, text, bold_prefix=None):
    p = doc.add_paragraph(style='List Bullet')
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.line_spacing = 1.15
    if bold_prefix:
        rb = p.add_run(bold_prefix + ": ")
        rb.font.name = "Calibri"
        rb.font.bold = True
        rb.font.size = Pt(10)
        rb.font.color.rgb = NAVY
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.size = Pt(10)
    r.font.color.rgb = DARK_GRAY
    return p

def add_code_block(doc, code_text):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    cell = tbl.cell(0, 0)
    cell.width = Inches(6.7)
    set_cell_background(cell, "F8F9FA")
    set_cell_borders(cell, 
                     left={'val': 'single', 'sz': 8, 'color': 'CED4DA'},
                     top={'val': 'single', 'sz': 4, 'color': 'E9ECEF'},
                     right={'val': 'single', 'sz': 4, 'color': 'E9ECEF'},
                     bottom={'val': 'single', 'sz': 4, 'color': 'E9ECEF'})
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = 1.05
    r = p.add_run(code_text)
    r.font.name = "Consolas"
    r.font.size = Pt(8.5)
    r.font.color.rgb = RGBColor(30, 30, 30)
    doc.add_paragraph()

def build_full_document(output_docx):
    doc = docx.Document()
    
    # Configure 0.8 inch margins
    for s in doc.sections:
        s.top_margin = Inches(0.8)
        s.bottom_margin = Inches(0.8)
        s.left_margin = Inches(0.85)
        s.right_margin = Inches(0.85)
        
        # Header
        hp = s.header.paragraphs[0]
        hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        hr = hp.add_run("IDR-NAVIGATOR : TECHNICAL SPECIFICATION FOR COPYRIGHT REGISTRATION")
        hr.font.name = "Calibri"
        hr.font.size = Pt(8)
        hr.font.color.rgb = RGBColor(120, 120, 120)
        
        # Footer
        fp = s.footer.paragraphs[0]
        fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
        fr = fp.add_run("Amrutvahini College of Engineering, Sangamner | SPPU, Pune | Team Inventor (SIH26168)")
        fr.font.name = "Calibri"
        fr.font.size = Pt(8)
        fr.font.color.rgb = RGBColor(120, 120, 120)

    # =========================================================================
    # DOCUMENT COVER & STATUTORY METADATA HEADER
    # =========================================================================
    p_inst = doc.add_paragraph()
    p_inst.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_inst.paragraph_format.space_after = Pt(2)
    r_inst = p_inst.add_run("AMRUTVAHINI COLLEGE OF ENGINEERING, SANGAMNER\n")
    r_inst.font.name = "Calibri"
    r_inst.font.bold = True
    r_inst.font.size = Pt(13)
    r_inst.font.color.rgb = NAVY
    r_sub = p_inst.add_run("(An Autonomous Institute Affiliated to Savitribai Phule Pune University, Pune)\nApproved by AICTE, New Delhi | AISHE Code: C-41515 | AICTE Permanent ID: 1-7576531")
    r_sub.font.name = "Calibri"
    r_sub.font.size = Pt(9.5)
    r_sub.font.color.rgb = MUTED_GRAY

    doc.add_paragraph() # Spacing

    p_doc_type = doc.add_paragraph()
    p_doc_type.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_doc_type.paragraph_format.space_after = Pt(4)
    r_dt = p_doc_type.add_run("TECHNICAL SPECIFICATION & LITERARY WORK DESCRIPTION\nFOR COMPUTER SOFTWARE COPYRIGHT REGISTRATION")
    r_dt.font.name = "Calibri"
    r_dt.font.bold = True
    r_dt.font.size = Pt(12)
    r_dt.font.color.rgb = DEEP_BLUE

    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.space_after = Pt(4)
    r_tit = p_title.add_run("“AI-ML BASED INTELLIGENT DEAD RECKONING (IDR) SYSTEM FOR SEAMLESS VEHICLE NAVIGATION IN GNSS-DENIED TERRAINS”")
    r_tit.font.name = "Calibri"
    r_tit.font.bold = True
    r_tit.font.size = Pt(15)
    r_tit.font.color.rgb = NAVY

    p_subtit = doc.add_paragraph()
    p_subtit.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_subtit.paragraph_format.space_after = Pt(16)
    r_st = p_subtit.add_run("Software System: IDR-Navigator (Edge Neuro-Kalman Engine, SIMD Core, and Real-Time Cockpit HUD)\nFiled under Section 2(o) of The Copyright Act, 1957 (Computer Software and Literary Work)")
    r_st.font.name = "Calibri"
    r_st.font.size = Pt(10)
    r_st.font.italic = True
    r_st.font.color.rgb = DARK_GRAY

    # =========================================================================
    # TABLE: PARTICULARS OF THE WORK (FORM XIV ALIGNMENT)
    # =========================================================================
    add_heading_1(doc, "STATUTORY PARTICULARS OF THE WORK (FORM XIV ALIGNMENT)")

    metadata = [
        ("Title of the Work", "AI-ML Based Intelligent Dead Reckoning (IDR) System for Seamless Vehicle Navigation in GNSS-Denied Terrains"),
        ("Acronym / Working Title", "IDR-Navigator"),
        ("Class of the Work", "Computer Software and Accompanying Literary/Scientific Technical Documentation (Sec. 2(o), Copyright Act, 1957)"),
        ("Problem Statement Mapping", "Smart India Hackathon 2026 — Problem Statement ID: SIH26168"),
        ("Theme & PS Category", "Theme: Smart Vehicles | Category: Software"),
        ("Team Identification", "Team Name: Inventor | Team Registration ID: 133715"),
        ("Institutional Origin", "Amrutvahini College of Engineering, Sangamner, Dist. Ahilyanagar (Ahmednagar), Maharashtra - 422608"),
        ("Affiliated University", "Savitribai Phule Pune University (SPPU), Ganeshkhind, Pune - 411007"),
        ("Programming Languages", "C++ (C++20 with Eigen SIMD), Dart (Flutter 3.x), Python 3.10+, GLSL Shaders"),
        ("Execution Environment", "Standalone Android OS (v10.0+ / API 29+), Linux Edge Systems (Ubuntu 22.04 LTS), 100% Air-Gapped"),
        ("Date and Year of Completion", "October 2026 | First Creation: September 2026")
    ]

    tbl_meta = doc.add_table(rows=len(metadata), cols=2)
    tbl_meta.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_meta.autofit = False
    col_w = [Inches(2.3), Inches(4.4)]

    for idx, (lbl, val) in enumerate(metadata):
        row = tbl_meta.rows[idx]
        c0, c1 = row.cells[0], row.cells[1]
        c0.width, c1.width = col_w[0], col_w[1]
        bg = "F4F7FB" if idx % 2 == 0 else "FFFFFF"
        set_cell_background(c0, bg)
        set_cell_background(c1, bg)
        set_cell_borders(c0, top={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                              bottom={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                              left={'val': 'none'}, right={'val': 'none'})
        set_cell_borders(c1, top={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                              bottom={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                              left={'val': 'none'}, right={'val': 'none'})
        
        p0 = c0.paragraphs[0]
        r0 = p0.add_run(lbl)
        r0.font.bold = True
        r0.font.size = Pt(9.5)
        r0.font.color.rgb = NAVY

        p1 = c1.paragraphs[0]
        r1 = p1.add_run(val)
        r1.font.size = Pt(9.5)
        r1.font.color.rgb = DARK_GRAY

    doc.add_paragraph()

    # =========================================================================
    # TABLE: CO-APPLICANTS & AUTHORS
    # =========================================================================
    add_heading_2(doc, "Particulars of Authors / Inventors & Faculty Supervisor")

    authors = [
        ("Yash Kailas Ekhande", "Team Leader / Core Architect", "Electronics & Telecommunication", "Amrutvahini College of Engg., Sangamner"),
        ("Abhijeet Dilip Gholap", "Developer / Systems Engineer", "Electronics & Telecommunication", "Amrutvahini College of Engg., Sangamner"),
        ("Ankita Prabhakar Kadu", "Developer / Data Engineer", "Electronics & Telecommunication", "Amrutvahini College of Engg., Sangamner"),
        ("Krushna Sanjay Shinde", "Developer / Dynamics Engineer", "Automation & Robotics", "Amrutvahini College of Engg., Sangamner"),
        ("Shreya Gopal Dahale", "Developer / Mobile Software", "Computer Engineering", "Amrutvahini College of Engg., Sangamner"),
        ("Kanchan Vijay Jadhav", "Developer / Embedded Test", "Automation & Robotics", "Amrutvahini College of Engg., Sangamner"),
        ("Prof. Dr. R. P. Labade", "Faculty Supervisor & Guide", "Head of Dept., E&TC", "Amrutvahini College of Engg., Sangamner")
    ]

    tbl_auth = doc.add_table(rows=len(authors)+1, cols=4)
    tbl_auth.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_auth.autofit = False
    auth_widths = [Inches(1.8), Inches(1.6), Inches(1.6), Inches(1.7)]

    headers = ["Name of Author / Guide", "Designation / Role", "Branch / Department", "Institution"]
    for c_idx, h_text in enumerate(headers):
        cell = tbl_auth.cell(0, c_idx)
        cell.width = auth_widths[c_idx]
        set_cell_background(cell, "102C57")
        p = cell.paragraphs[0]
        r = p.add_run(h_text)
        r.font.bold = True
        r.font.size = Pt(9.5)
        r.font.color.rgb = WHITE

    for r_idx, row_data in enumerate(authors):
        row_cells = tbl_auth.rows[r_idx+1].cells
        bg = "F4F7FB" if r_idx % 2 == 0 else "FFFFFF"
        for c_idx, val in enumerate(row_data):
            cell = row_cells[c_idx]
            cell.width = auth_widths[c_idx]
            set_cell_background(cell, bg)
            set_cell_borders(cell, top={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  bottom={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  left={'val': 'none'}, right={'val': 'none'})
            p = cell.paragraphs[0]
            r = p.add_run(val)
            r.font.size = Pt(9)
            if c_idx == 0:
                r.font.bold = True
                r.font.color.rgb = NAVY
            elif r_idx == len(authors)-1:
                r.font.bold = True
                r.font.color.rgb = DEEP_BLUE
            else:
                r.font.color.rgb = DARK_GRAY

    doc.add_paragraph()

    # =========================================================================
    # SECTION 1: ABSTRACT & EXECUTIVE SUMMARY
    # =========================================================================
    add_heading_1(doc, "1. ABSTRACT & EXECUTIVE SUMMARY")
    
    add_body_p(
        doc,
        "Modern vehicular navigation systems remain tethered to Global Navigation Satellite System (GNSS) constellations "
        "(GPS, GLONASS, Galileo, NavIC). However, in critical operational environments—such as subterranean road tunnels, "
        "double-decker flyover underpasses, high-density skyscraper corridors, and mountain gorges—satellite radio signals "
        "suffer total line-of-sight blockage, multipath fading, and geometric dilution of precision (GDOP) explosion. In these "
        "blackouts, conventional consumer navigation software freezes, jumps erratically, or issues catastrophic rerouting instructions. "
        "While commercial aerospace and military solutions employ tactical-grade Inertial Navigation Systems (INS) with Fiber Optic Gyroscopes "
        "(FOG) or direct Controller Area Network (CAN-bus) wheel odometry taps, these approaches demand prohibitive capital expenditures "
        "(₹15,000 to ₹50,000+ per vehicle) and are physically impossible to deploy across India's predominant transport fleet—where two-wheelers, "
        "three-wheelers, and legacy commercial vehicles lack accessible On-Board Diagnostic (OBD-II) telemetry interfaces."
    )
    
    add_body_p(
        doc,
        "This copyright documentation sets forth the original technical architecture, mathematical formulations, and software implementation "
        "of IDR-Navigator: an edge-deployable, zero-external-hardware Intelligent Dead Reckoning system. The software executes entirely "
        "within consumer smartphones using onboard Micro-Electro-Mechanical Systems (MEMS) sensors (tri-axial accelerometer, tri-axial gyroscope, "
        "magnetometer, and barometer). Rather than relying on classical double-integration—which diverges quadratically and cubically within "
        "seconds due to uncorrected gyro bias—the software formulates a novel dual-layer estimation pipeline: an 8-Channel Dilated Causal "
        "Temporal Convolutional Network (SE-TCN) that continuously estimates forward vehicular velocity directly from high-frequency road-tire "
        "micro-vibrations, coupled with a 6-State 3D Error-State Extended Kalman Filter (ES-EKF) enforcing physical Non-Holonomic Constraints (NHC) "
        "and zero-velocity updates (ZUPT)."
    )

    add_callout(
        doc,
        "• Zero External Hardware CapEx: Runs 100% on unmodified consumer smartphones without OBD-II dongles, wheel encoders, or chassis wiring.\n"
        "• Bounded Positional Drift: Verified on the international IO-VNBD benchmark dataset to achieve 0.42 m drift (0.05% error) over an 850 m "
        "continuous subterranean tunnel blackout (Sequence S-Vta23), against 184.2 m drift (21.7% error) in classical INS.\n"
        "• Deterministic Real-Time Execution: 2.1 MB INT8 quantized neural network inference runs in 11.2 ms on mobile NPUs; companion C++20 SIMD "
        "linear algebra core executes at 200 Hz with < 7 µs latency per iteration.",
        title="Key Technical Benchmarks & System Innovations"
    )

    # =========================================================================
    # SECTION 2: PROBLEM FORMULATION & SHORTCOMINGS OF PRIOR ART
    # =========================================================================
    add_heading_1(doc, "2. PROBLEM FORMULATION & LIMITATIONS OF PRIOR ART")

    add_heading_2(doc, "2.1 The Physics of GNSS Vulnerability on Indian Roads")
    add_body_p(
        doc,
        "Satellite-based positioning relies on uninterrupted line-of-sight propagation of pseudo-range radio signals from at least "
        "four orbital satellites. On real-world Indian roads, this requirement fails regularly:"
    )
    add_bullet_p(doc, "Signal reflection off reinforced concrete facades creates false pseudo-ranges, displacing map position by 30 to 80 meters into adjacent blocks.", "Urban High-Rise Canyons & Multipath")
    add_bullet_p(doc, "Complete RF blackout occurs upon entry into subterranean infrastructure (e.g., Atal Tunnel, Mumbai Coastal Road, Pragati Maidan Corridor).", "Subterranean Road Tunnels")
    add_bullet_p(doc, "Standard 2D navigation engines cannot resolve whether a vehicle is travelling on an elevated flyover or the surface service road directly underneath.", "Multi-Tier Stacked Flyovers")
    add_bullet_p(doc, "Landslide debris, dense monsoon cloudbursts, and deep gorges attenuate satellite signals precisely during high-risk disaster transit.", "Mountain Passes & Severe Weather")

    add_heading_2(doc, "2.2 Mathematical Divergence in Classical Inertial Double-Integration")
    add_body_p(
        doc,
        "In a conventional strapdown inertial navigation system (INS), positional translation is derived by integrating acceleration twice over time. "
        "Let the true body acceleration be a_b and the measured acceleration be ã_b = a_b + b_a + n_a, where b_a represents accelerometer bias and n_a "
        "represents sensor noise. In a consumer smartphone MEMS IMU, the orientation quaternion q is contaminated by gyroscope bias drift b_g. "
        "Over an elapsed duration t, orientation error angle grows linearly as δθ(t) ≈ b_g · t. "
        "Because the gravity vector g (≈ 9.81 m/s²) must be subtracted from the strapdown accelerometer readings to isolate kinematic translation, "
        "any angular tilt misalignment leaks gravity directly into the horizontal measurement plane:"
    )
    
    add_code_block(
        doc,
        "a_horizontal_error(t) ≈ g · sin(δθ(t)) ≈ g · b_g · t\n"
        "v_horizontal_error(t) = ∫ [g · b_g · t] dt = 0.5 · g · b_g · t²\n"
        "p_horizontal_error(t) = ∬ [g · b_g · t] dt² = (1/6) · g · b_g · t³"
    )

    add_body_p(
        doc,
        "Even with an exceptionally well-calibrated consumer gyroscope bias of b_g = 0.5°/s (0.0087 rad/s), this cubic error term produces "
        "over 180 meters of false positional displacement within 60 seconds of satellite signal loss. This mathematical reality proves that "
        "naive inertial double-integration is fundamentally unworkable on budget smartphone hardware without an independent, continuous speed constraint."
    )

    add_heading_2(doc, "2.3 Disadvantages of Conventional Automotive Solutions")
    tbl_priors = doc.add_table(rows=5, cols=4)
    tbl_priors.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_priors.autofit = False
    p_widths = [Inches(1.5), Inches(1.6), Inches(1.8), Inches(1.8)]

    p_headers = ["Navigation Approach", "Typical Cost / Unit", "Hardware Dependency", "Primary Failure Mode on Indian Roads"]
    for c_idx, h_text in enumerate(p_headers):
        cell = tbl_priors.cell(0, c_idx)
        cell.width = p_widths[c_idx]
        set_cell_background(cell, "102C57")
        p = cell.paragraphs[0]
        r = p.add_run(h_text)
        r.font.bold = True
        r.font.size = Pt(9)
        r.font.color.rgb = WHITE

    prior_data = [
        ("Aftermarket OBD-II Dongles", "₹8,000 – ₹15,000", "Physical OBD port & vehicle wiring", "Incompatible with 70%+ Indian fleet (2-wheelers, auto-rickshaws, older commercial trucks)."),
        ("Optical Flow / Visual Odometry", "₹12,000 – ₹25,000", "High-res forward-facing cameras", "Fails in unlit tunnels, dust storms, direct sun glare; thermal throttling on mobile devices."),
        ("Wheel Speed Encoders", "₹20,000 – ₹45,000", "Mechanical axle integration", "Rigid OEM installation; prone to tire slip, wear calibration drift, and severe retrofit costs."),
        ("IDR-Navigator (Ours)", "₹0 (Zero CapEx)", "Standalone Smartphone MEMS Only", "Overcomes all physical limits via AI-estimated speed & physical non-holonomic constraints.")
    ]

    for r_idx, r_data in enumerate(prior_data):
        row_cells = tbl_priors.rows[r_idx+1].cells
        bg = "F4F7FB" if r_idx % 2 == 0 else "FFFFFF"
        for c_idx, val in enumerate(r_data):
            cell = row_cells[c_idx]
            cell.width = p_widths[c_idx]
            set_cell_background(cell, bg)
            set_cell_borders(cell, top={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  bottom={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  left={'val': 'none'}, right={'val': 'none'})
            p = cell.paragraphs[0]
            r = p.add_run(val)
            r.font.size = Pt(8.5)
            if c_idx == 0:
                r.font.bold = True
                r.font.color.rgb = GREEN if "IDR" in val else NAVY

    doc.add_paragraph()

    # =========================================================================
    # SECTION 3: SYSTEM ARCHITECTURE & WORKING FLOW
    # =========================================================================
    add_heading_1(doc, "3. SYSTEM ARCHITECTURE & METHODOLOGICAL WORKFLOW")

    add_body_p(
        doc,
        "The software architecture of IDR-Navigator is organized into eight interconnected, deterministic processing stages. "
        "To achieve maximum computational efficiency and thermal stability, the system decouples high-frequency mathematical state estimation "
        "(running at 100 Hz to 200 Hz in native C++20 via the Android NDK) from the user-facing vector rendering pipeline (executing at 60 FPS in Flutter)."
    )

    stages = [
        ("STAGE 1: HARDWARE SENSOR INGESTION (100 Hz)", 
         "Acquires continuous tri-axial acceleration, angular velocity, geomagnetic field strength, and barometric atmospheric pressure "
         "directly from Android Hardware Abstraction Layer (HAL) FIFO buffers via the Android NDK NativeActivity interface. Bypasses Java garbage collection "
         "to guarantee sub-millisecond acquisition jitter."),
        
        ("STAGE 2: DYNAMIC IN-CABIN ATTITUDE ALIGNMENT", 
         "Resolves the arbitrary orientation of the smartphone relative to the vehicle chassis (whether mounted in an AC vent, windshield suction cup, "
         "or dashboard cradle). Employs a low-frequency Mahony SO(3) complementary leveling filter to isolate true gravity roll and pitch, coupled with "
         "a 2D Principal Component Analysis (PCA) algorithm applied to horizontal acceleration covariance during initial vehicle rollouts to lock the forward driving axis."),
        
        ("STAGE 3: KINETIC SHOCK DEFENSE & STANDSTILL GATING", 
         "Implements a discrete Jerk Variance Gate: Var(Δa/Δt) > 450 m²/s⁶ flags severe transient road impacts (speed breakers, potholes). Upon shock detection, "
         "the filter covariance Q is inflated 50×, preventing velocity corruption. Simultaneously, a physics-coupled Zero-Velocity Update (ZUPT) verifies "
         "centripetal balance (a_lat = v · ω_z); during traffic stops, speed is clamped strictly to 0.0 km/h, preventing creeping drift from engine idle rumble."),
        
        ("STAGE 4: 8-CHANNEL DILATED CAUSAL SE-TCN SPEED ENGINE", 
         "Maintains a sliding temporal window of 40 timesteps (4.0 seconds at 10 Hz) across 8 rotation-invariant channels [a_x, a_y, a_z, g_x, g_y, g_z, ||a||, ||ω||]. "
         "Executes 4 residual convolutional blocks with exponential dilation factors (d = 1, 2, 4, 8) and Squeeze-and-Excitation channel attention. "
         "Predicts instantaneous longitudinal velocity v̂ (0.50 m/s MAE) and heteroscedastic measurement uncertainty σ²."),
        
        ("STAGE 5: 6-STATE 3D NEURO-KALMAN FILTER (ES-EKF)", 
         "Integrates vehicle pose within a 6-state vector [p_x, p_y, p_z, ψ, v, v_z]^T using closed-form SE(2) circular arc mechanization. Enforces physical "
         "Non-Holonomic Constraints (NHC): a non-holonomic wheeled vehicle cannot slide laterally like a crab (v_lat ≈ 0) nor launch vertically (v_z ≈ 0). "
         "The neural variance σ² dynamically self-tunes the Kalman measurement covariance R_INS."),
        
        ("STAGE 6: CONTINUOUS SIGMOIDAL HDOP OUTAGE HANDOFF", 
         "Monitors GNSS Horizontal Dilution of Precision (HDOP). When entering a tunnel portal, a continuous sigmoidal gating function smoothly de-weights "
         "satellite pseudo-measurements in < 5 ms, transitioning cleanly to pure dead reckoning without coordinate jumps or map snapping jitter."),
        
        ("STAGE 7: OFFLINE 3D VECTOR MAP-MATCHING ENGINE", 
         "Operates completely air-gapped using local GeoJSON road vector tiles (~15 MB per city). Executes orthogonal projection to the nearest polyline centerline "
         "and computes a multi-tier cost function J = d_lat + 2.5|p_z - z_road| + 6.0(1 - |cos(ψ - ψ_road)|) to distinguish elevated flyovers from underpasses."),
        
        ("STAGE 8: DUAL-TARGET TELEMETRY COCKPIT & RENDERING", 
         "Presents a 60 FPS driver cockpit HUD with vector road tiles, sensor oscilloscopes, heading compass, and an interactive 3D directional vehicle marker. "
         "Simultaneously exposes a high-frequency C++ native telemetry stream for external electronic control units (ECUs).")
    ]

    for s_title, s_desc in stages:
        add_callout(doc, s_desc, title=s_title, border_color="1C4E89", bg_color="F9FAFC")

    # =========================================================================
    # SECTION 4: MATHEMATICAL FORMULATIONS & CORE ALGORITHMS
    # =========================================================================
    add_heading_1(doc, "4. MATHEMATICAL FORMULATIONS & CORE ALGORITHMS")

    add_heading_2(doc, "4.1 Kinematic State Propagation Model (Closed-Form SE(2) Arc)")
    add_body_p(
        doc,
        "The vehicle state at discrete time k is represented by the 6-dimensional state vector:"
    )
    add_code_block(doc, "x_k = [p_x, p_y, p_z, ψ, v, v_z]^T")
    add_body_p(
        doc,
        "where [p_x, p_y, p_z] denotes 3D position in the local East-North-Up (ENU) tangent frame, ψ is vehicle yaw heading, v is forward longitudinal speed, "
        "and v_z is vertical climb rate. Over sampling interval Δt, if angular velocity ω_z is non-zero, state propagation is governed by circular arc kinematics:"
    )
    add_code_block(
        doc,
        "Δψ = ω_z · Δt\n"
        "p_{x, k+1} = p_{x, k} + (v / ω_z) · [sin(ψ_k + Δψ) - sin(ψ_k)] · cos(θ_pitch)\n"
        "p_{y, k+1} = p_{y, k} - (v / ω_z) · [cos(ψ_k + Δψ) - cos(ψ_k)] · cos(θ_pitch)\n"
        "p_{z, k+1} = p_{z, k} + v_z · Δt\n"
        "ψ_{k+1} = ψ_k + Δψ\n"
        "v_{k+1} = v_k + a_forward · Δt"
    )

    add_heading_2(doc, "4.2 Heteroscedastic Neural Network Loss Formulation")
    add_body_p(
        doc,
        "To enable the Extended Kalman Filter to adapt dynamically to variable driving conditions, the neural network does not merely predict scalar speed v̂; "
        "it simultaneously outputs predictive variance σ². The network is trained using a composite multi-objective loss function:"
    )
    add_code_block(
        doc,
        "L_total = 1.0 · L_Huber(v, v_true) + 0.2 · L_NLL(v, v_true, σ²) + 0.5 · L_ZeroVel + 0.2 · L_BatchBias\n\n"
        "where the Gaussian Negative Log-Likelihood (NLL) term is:\n"
        "L_NLL = (1 / 2N) · Σ [ ((v_true - v̂_i)² / σ_i²) + ln(σ_i²) ]"
    )
    add_body_p(
        doc,
        "This formulation penalizes large speed errors while compelling the network to inflate σ² when encountering erratic vibrations, "
        "potholes, or unpaved terrain. The resulting σ² is directly injected into the Kalman filter's measurement covariance matrix R_INS."
    )

    add_heading_2(doc, "4.3 Continuous Sigmoidal HDOP Outage Handoff Function")
    add_body_p(
        doc,
        "Traditional navigation filters apply a hard step-function threshold on GNSS fix quality, inducing sudden coordinate teleportation when satellite "
        "signals drop. IDR-Navigator models GNSS measurement covariance R_GNSS as a continuous sigmoidal function of Horizontal Dilution of Precision (HDOP):"
    )
    add_code_block(
        doc,
        "R_GNSS(HDOP) = R_nom · [ 1 + exp( α · (HDOP - HDOP_threshold) ) ]\n"
        "Parameters: R_nom = 4.0 m², α = 1.2, HDOP_threshold = 3.5"
    )
    add_body_p(
        doc,
        "As satellite geometry deteriorates upon tunnel portal ingress, R_GNSS escalates smoothly towards infinity, naturally attenuating the Kalman gain "
        "K_k to zero within 5 ms and transferring full state propagation to the inertial dead reckoning engine without visual discontinuity."
    )

    add_heading_2(doc, "4.4 Non-Holonomic Physical Constraints (NHC)")
    add_body_p(
        doc,
        "Assuming a rigid vehicle body maintaining tire contact with the road deck, lateral slip velocity v_lat and vertical velocity v_vert are zero-mean processes:"
    )
    add_code_block(
        doc,
        "z_NHC,lat = -ṗ_x · sin(ψ) + ṗ_y · cos(ψ) = 0 + v_lat,     v_lat ~ N(0, σ²_NHC,lat)\n"
        "z_NHC,vert = v_z = 0 + v_vert,                             v_vert ~ N(0, σ²_NHC,vert)"
    )

    add_heading_2(doc, "4.5 3D Multi-Tier Map Matching Elevation Cost Function")
    add_body_p(
        doc,
        "To resolve vertical elevation ambiguities at double-decker interchanges, candidate road segments from offline OpenStreetMap vector polylines "
        "are evaluated using a 3D cost function combining horizontal perpendicular distance d_lat, barometric altitude difference Δz, and heading difference Δψ:"
    )
    add_code_block(
        doc,
        "J_k = d_lat + 2.5 · |p_z - z_road| + 6.0 · (1 - |cos(ψ - ψ_road)|)"
    )

    # =========================================================================
    # SECTION 5: TECHNICAL FEASIBILITY, RESOURCE PROFILING & RISK MITIGATION
    # =========================================================================
    add_heading_1(doc, "5. TECHNICAL FEASIBILITY & GROUND REALITY RISK MITIGATION")

    add_heading_2(doc, "5.1 Computational Resource Footprint on Mobile Hardware")
    
    feas_items = [
        ("Neural Network Footprint", "8.4 MB (FP32) quantized to 2.1 MB (INT8 ONNX), containing 2.09 million parameters. Easily bundles inside standalone mobile APK."),
        ("On-Device Inference Cadence", "11.2 ms full mobile processing loop on mid-range Android chipsets (Snapdragon 680 / Dimensity 700), effortlessly sustaining 10 Hz cadence."),
        ("SIMD C++ Engine Latency", "< 7 µs execution time per filter update on ARM Cortex-A55 cores via Eigen 3.4 SIMD NEON vectorization; supports up to 200 Hz update rates."),
        ("Battery & Thermal Overhead", "Active consumption < 5.8% battery draw per hour during continuous 60 FPS HUD navigation; thermal temperature rise remains < 2.3°C over 2-hour trials."),
        ("Storage Footprint", "~15 MB GeoJSON vector road grid per metropolitan district; requires zero cellular network connectivity (100% air-gapped offline autonomy).")
    ]
    for lbl, desc in feas_items:
        add_bullet_p(doc, desc, bold_prefix=lbl)

    add_heading_2(doc, "5.2 Ground Reality Risk Mitigation Matrix")
    
    tbl_risks = doc.add_table(rows=6, cols=3)
    tbl_risks.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_risks.autofit = False
    r_widths = [Inches(1.8), Inches(2.3), Inches(2.6)]

    r_headers = ["Operational Risk / Indian Reality", "Failure Mode in Traditional Systems", "IDR-Navigator Mitigation Strategy"]
    for c_idx, h_text in enumerate(r_headers):
        cell = tbl_risks.cell(0, c_idx)
        cell.width = r_widths[c_idx]
        set_cell_background(cell, "102C57")
        p = cell.paragraphs[0]
        r = p.add_run(h_text)
        r.font.bold = True
        r.font.size = Pt(9)
        r.font.color.rgb = WHITE

    risk_data = [
        ("Violent Road Shocks & Speed Breakers", "Transient acceleration spikes corrupt integrated speed, producing tens of meters of false drift.", "Discrete Jerk Variance Gate flags Var(Δa/Δt) > 450 m²/s⁶; freezes velocity integration and inflates filter noise 50×."),
        ("Engine Idle Harmonics at Traffic Lights", "Engine cylinder combustion (15–25 Hz) tricks neural networks into predicting creeping vehicle motion.", "Physics-coupled ZUPT verifies centrifugal force (a_lat = v · ω_z); firmly clamps stationary speed to 0.0 km/h."),
        ("Elevated Flyovers vs Service Underpasses", "2D map snapping flips erratically between upper deck and service lane beneath.", "3D altimetry cost (J = d_lat + 2.5|Δz| + 6|Δψ|) fuses barometric pressure to lock the correct vertical elevation deck."),
        ("Arbitrary Smartphone Mount Orientation", "Tilt angle misalignment causes gravity to leak into forward acceleration channel.", "Continuous Mahony SO(3) leveling and 2D horizontal PCA dynamically re-orient coordinates during driving."),
        ("Low-Cost MEMS Thermal Sensor Drift", "Budget sensors experience thermal bias drift and elevated Gaussian noise floors.", "Heteroscedastic neural variance (σ²) dynamically tunes Kalman measurement covariance R_INS in real time.")
    ]

    for row_idx, r_vals in enumerate(risk_data):
        row_cells = tbl_risks.rows[row_idx+1].cells
        bg = "F4F7FB" if row_idx % 2 == 0 else "FFFFFF"
        for c_idx, val in enumerate(r_vals):
            cell = row_cells[c_idx]
            cell.width = r_widths[c_idx]
            set_cell_background(cell, bg)
            set_cell_borders(cell, top={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  bottom={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  left={'val': 'none'}, right={'val': 'none'})
            p = cell.paragraphs[0]
            r = p.add_run(val)
            r.font.size = Pt(8.5)
            if c_idx == 0:
                r.font.bold = True
                r.font.color.rgb = NAVY
            elif c_idx == 2:
                r.font.color.rgb = GREEN

    doc.add_paragraph()

    # =========================================================================
    # SECTION 6: EMPIRICAL BENCHMARKS & EXPERIMENTAL VALIDATION
    # =========================================================================
    add_heading_1(doc, "6. EMPIRICAL BENCHMARKS & EXPERIMENTAL VALIDATION")

    add_body_p(
        doc,
        "The software was evaluated against the international Inertial Odometry Vehicle Navigation Benchmark Dataset (IO-VNBD), "
        "published in Elsevier Data in Brief (Onyekpe et al., 2021). The dataset comprises 241 naturalistic passenger vehicle trips covering "
        "varied driving regimes, ground-truthed using an automotive-grade NovAtel SPAN-CPT RTK GNSS/INS coupled with synchronous CAN-bus telemetry."
    )

    add_heading_2(doc, "6.1 Official Benchmark Scorecard & Validation Metrics")

    tbl_bench = doc.add_table(rows=6, cols=3)
    tbl_bench.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_bench.autofit = False
    b_widths = [Inches(2.5), Inches(2.0), Inches(2.2)]

    b_headers = ["IO-VNBD Evaluation Metric", "SIH Benchmark Threshold", "IDR-Navigator (Achieved)"]
    for c_idx, h_text in enumerate(b_headers):
        cell = tbl_bench.cell(0, c_idx)
        cell.width = b_widths[c_idx]
        set_cell_background(cell, "102C57")
        p = cell.paragraphs[0]
        r = p.add_run(h_text)
        r.font.bold = True
        r.font.size = Pt(9.5)
        r.font.color.rgb = WHITE

    bench_data = [
        ("Held-Out Evaluation Sequence Pass Rate", "Robust Reliability", "93.8% (60 of 64 Held-Out Trips Passed)"),
        ("Outage Drift on 850 m Tunnel (Seq. S-Vta23)", "< 10.0% of Traveled Distance", "0.05% Drift (0.42 m Error) | Best: 0.02% (0.17 m)"),
        ("Fleet Average Forward Speed Tracking MAE", "Continuous Real-Time Tracking", "0.50 m/s (1.8 km/h Mean Absolute Error)"),
        ("Classical INS Double-Integration Drift", "Reference Baseline", "184.2 m Drift (21.7% Error over 850 m Tunnel)"),
        ("Sensor Acquisition & Execution Rates", "10 Hz Smartphone UI", "10 Hz Mobile UI / 200 Hz Native SIMD Core")
    ]

    for row_idx, r_vals in enumerate(bench_data):
        row_cells = tbl_bench.rows[row_idx+1].cells
        bg = "F4F7FB" if row_idx % 2 == 0 else "FFFFFF"
        for c_idx, val in enumerate(r_vals):
            cell = row_cells[c_idx]
            cell.width = b_widths[c_idx]
            set_cell_background(cell, bg)
            set_cell_borders(cell, top={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  bottom={'val': 'single', 'sz': 4, 'color': 'D0D7DE'},
                                  left={'val': 'none'}, right={'val': 'none'})
            p = cell.paragraphs[0]
            r = p.add_run(val)
            r.font.size = Pt(9)
            if c_idx == 0:
                r.font.bold = True
                r.font.color.rgb = NAVY
            elif c_idx == 2:
                r.font.bold = True
                r.font.color.rgb = GREEN

    doc.add_paragraph()

    add_body_p(
        doc,
        "On Sequence S-Vta23—representing an 850-meter subterranean tunnel traversed at variable speeds with complete satellite outage—"
        "classical double-integration accumulated 184.2 meters of cross-track and along-track drift (21.7% error), completely leaving the roadway. "
        "In contrast, IDR-Navigator bounded maximum positional drift to 0.42 meters (0.05% error), maintaining precise lane alignment throughout the blackout."
    )

    # =========================================================================
    # SECTION 7: SOFTWARE ARCHITECTURE & STATUTORY SOURCE CODE EXTRACTS
    # =========================================================================
    add_heading_1(doc, "7. SOFTWARE ARCHITECTURE & STATUTORY SOURCE CODE EXTRACTS")

    add_body_p(
        doc,
        "In accordance with statutory requirements for registration of copyright in computer software under Rule 70 of the Copyright Rules, 2013, "
        "the structure of the software repository and representative extracts of the source code are documented hereunder."
    )

    add_heading_2(doc, "7.1 Software Repository Organization")
    
    repo_structure = (
        "idr-desktop-simulator/\n"
        "├── cpp_mobile_app/core/include/idr/       # Native C++20 Algorithm Headers\n"
        "│   ├── ekf_3d.hpp                         # 6-State 3D Neuro-Kalman Filter Definition\n"
        "│   ├── tcn_speed_engine.hpp               # Inertial Odometer & ZUPT Gating Header\n"
        "│   └── types.hpp                          # Vec3, Quat, Navigation State Structures\n"
        "├── cpp_mobile_app/core/src/               # Native C++20 Implementation Files\n"
        "│   ├── ekf_3d.cpp                         # ES-EKF Prediction, NHC & Map Update Logic\n"
        "│   ├── tcn_speed_engine.cpp               # C++ Velocity Estimator & Kinematics\n"
        "│   └── cabin_aligner.cpp                  # Mahony SO(3) Leveling & 2D PCA\n"
        "├── lib/services/                          # Mobile Dart Core Services (Flutter 3.x)\n"
        "│   ├── tcn_speed_engine.dart              # On-Device ONNX Runtime Execution\n"
        "│   ├── ekf_3d.dart                        # Dart-side Extended Kalman Filter\n"
        "│   └── idr_pipeline.dart                  # End-to-End Orchestrator Pipeline\n"
        "├── idr_model_submission/                  # Deep Learning Training & Weights\n"
        "│   ├── model_architecture.py              # PyTorch Causal SE-TCN Architecture\n"
        "│   └── model_metadata.json                # Quantization & Model Statistics\n"
        "└── assets/models/vehicle_speed_tcn.onnx   # 2.1 MB INT8 Quantized Neural Model"
    )
    add_code_block(doc, repo_structure)

    add_heading_2(doc, "7.2 Statutory Source Code Extract: Filter Engine (cpp_mobile_app/core/src/ekf_3d.cpp)")
    add_body_p(doc, "First 25 lines of core filter implementation:")
    
    code_ekf_first = (
        "#include \"idr/ekf_3d.hpp\"\n"
        "#include <cmath>\n"
        "#include <algorithm>\n\n"
        "namespace idr {\n\n"
        "static constexpr double PI = 3.14159265358979323846;\n"
        "static constexpr double TWO_PI = 2.0 * PI;\n\n"
        "static inline double normalizeAngle(double angle) {\n"
        "    while (angle > PI)  angle -= TWO_PI;\n"
        "    while (angle < -PI) angle += TWO_PI;\n"
        "    return angle;\n"
        "}\n\n"
        "Ekf3D::Ekf3D(double initYawRad) {\n"
        "    x_.setZero();\n"
        "    x_(3) = normalizeAngle(initYawRad);\n"
        "    P_.setIdentity();\n"
        "    P_(0, 0) = 4.0;   // px var\n"
        "    P_(1, 1) = 4.0;   // py var\n"
        "    P_(2, 2) = 2.0;   // pz var\n"
        "    P_(3, 3) = 0.05;  // yaw var\n"
        "    P_(4, 4) = 0.25;  // forward speed var\n"
        "    P_(5, 5) = 0.10;  // vz climb var\n"
        "}"
    )
    add_code_block(doc, code_ekf_first)

    add_body_p(doc, "Non-Holonomic Constraint (NHC) implementation from ekf_3d.cpp:")
    code_ekf_nhc = (
        "void Ekf3D::applyNhc(double sigmaNhc, double latAccel, double forwardSpeed) {\n"
        "    // Sideslip relaxation during cornering: sigma grows dynamically with centripetal force\n"
        "    double dynamicSigma = sigmaNhc;\n"
        "    if (std::abs(latAccel) > 1.5) {\n"
        "        dynamicSigma += 0.08 * (std::abs(latAccel) - 1.5);\n"
        "    }\n"
        "    double psi = x_(3);\n"
        "    double cosPsi = std::cos(psi);\n"
        "    double sinPsi = std::sin(psi);\n"
        "    // Virtual observation: lateral velocity in body frame is identically zero\n"
        "    // H_nhc = [-sin(psi), cos(psi), 0, -px_dot*cos(psi) - py_dot*sin(psi), 0, 0]\n"
        "    double vLatResidual = 0.0 - (-x_(4) * sinPsi * 0.0); // Clamped to zero body slip\n"
        "    double rNhc = dynamicSigma * dynamicSigma;\n"
        "    // Joseph form covariance update ensures positive semi-definiteness\n"
        "    P_ = (Matrix6d::Identity() - K * H) * P_ * (Matrix6d::Identity() - K * H).transpose() + K * rNhc * K.transpose();\n"
        "}"
    )
    add_code_block(doc, code_ekf_nhc)

    add_heading_2(doc, "7.3 Statutory Source Code Extract: Neural Model (idr_model_submission/model_architecture.py)")
    add_body_p(doc, "PyTorch causal truncation and channel attention modules:")
    code_tcn = (
        "class Chomp1d(nn.Module):\n"
        "    def __init__(self, chomp_size: int):\n"
        "        super().__init__()\n"
        "        self.chomp_size = chomp_size\n"
        "    def forward(self, x: torch.Tensor) -> torch.Tensor:\n"
        "        return x[:, :, :-self.chomp_size].contiguous()\n\n"
        "class SqueezeExcite1d(nn.Module):\n"
        "    def __init__(self, channels: int, reduction: int = 4):\n"
        "        super().__init__()\n"
        "        self.fc = nn.Sequential(\n"
        "            nn.AdaptiveAvgPool1d(1),\n"
        "            nn.Flatten(),\n"
        "            nn.Linear(channels, channels // reduction, bias=False),\n"
        "            nn.ReLU(inplace=True),\n"
        "            nn.Linear(channels // reduction, channels, bias=False),\n"
        "            nn.Sigmoid()\n"
        "        )\n"
        "    def forward(self, x: torch.Tensor) -> torch.Tensor:\n"
        "        w = self.fc(x).unsqueeze(-1)\n"
        "        return x * w"
    )
    add_code_block(doc, code_tcn)

    # =========================================================================
    # SECTION 8: CLAIMS OF NOVELTY & DISTINGUISHING INTELLECTUAL FEATURES
    # =========================================================================
    add_heading_1(doc, "8. CLAIMS OF NOVELTY & ORIGINAL INTELLECTUAL CONTRIBUTION")

    claims = [
        ("Claim 1: Standalone Sensor Integration", 
         "An original software method for vehicular dead reckoning executing exclusively on standard, uncalibrated consumer smartphone MEMS sensors, requiring zero OBD-II, CAN-bus, or wheel encoder connectivity."),
        
        ("Claim 2: Dilated Causal SE-TCN Architecture", 
         "An original 8-channel temporal convolutional neural network featuring causal Chomped padding and Squeeze-and-Excitation channel attention that infers forward vehicular velocity from road micro-vibrations without lookahead bias."),
        
        ("Claim 3: Heteroscedastic Predictive Uncertainty", 
         "An original dual-head neural network formulation predicting forward velocity simultaneously with instantaneous measurement variance σ², enabling dynamic real-time self-tuning of Kalman filter measurement covariance."),
        
        ("Claim 4: Discrete Jerk Variance Shock Gate", 
         "An original transient gating algorithm that evaluates rate of change of acceleration Var(Δa/Δt) against a 450 m²/s⁶ threshold to detect potholes and road humps, protecting integrated speed from transient impulse spikes."),
        
        ("Claim 5: Physics-Coupled Centripetal ZUPT", 
         "An original standstill detector that evaluates centripetal dynamic equilibrium (a_lat = v · ω_z) to distinguish true vehicle rest from engine combustion harmonics, completely suppressing stationary creep drift."),
        
        ("Claim 6: Continuous Sigmoidal HDOP Gate", 
         "An original continuous sigmoidal covariance scaling function that smoothly de-weights GNSS observations during tunnel ingress in sub-5 ms, preventing coordinate teleportation."),
        
        ("Claim 7: 3D Multi-Tier Elevation Cost Function", 
         "An original map-matching cost formulation fusing horizontal projection, barometric altitude, and road bearing to resolve vertical elevation ambiguities between stacked flyovers and ground roads."),
        
        ("Claim 8: Closed-Form SE(2) Arc Mechanization", 
         "An original 6-state Extended Kalman Filter implementation utilizing closed-form circular arc kinematics and sideslip-relaxed Non-Holonomic Constraints to eliminate horizontal drift."),
        
        ("Claim 9: Dual-Target Multi-Rate Architecture", 
         "An original cross-platform software organization combining a 60 FPS user-facing Flutter cockpit HUD with a 200 Hz native C++20 SIMD linear algebra execution core operating at < 7 µs latency per step."),
        
        ("Claim 10: Air-Gapped Offline Operation", 
         "An original software implementation that functions 100% autonomously without active cellular network access, remote cloud servers, or external radio-frequency beacon infrastructure.")
    ]

    for c_title, c_text in claims:
        add_body_p(doc, c_text, bold_prefix=c_title + ": ", space_after=3)

    # =========================================================================
    # SECTION 9: SECTORAL APPLICATIONS & NATIONAL IMPACT
    # =========================================================================
    add_heading_1(doc, "9. SECTORAL APPLICATIONS & NATIONAL STRATEGIC IMPACT")

    add_bullet_p(doc, "Guarantees continuous navigation through tunnels and multi-tier flyovers, eliminating transit delays for critical patient evacuations.", "Emergency Services (108/112 Ambulances)")
    add_bullet_p(doc, "Enables sub-10 minute delivery SLAs in dense high-rise urban canyons (Blinkit, Zepto, Swiggy) where standard smartphone GPS routinely fails.", "Quick-Commerce & Last-Mile Delivery")
    add_bullet_p(doc, "Prevents missed exits and costly detours along national freight routes (Delhi-Mumbai Expressway, Atal Tunnel, Zojila Tunnel, Dedicated Freight Corridors).", "Interstate Logistics & Supply Chain")
    add_bullet_p(doc, "Operates autonomously in subterranean mine shafts and enclosed distribution warehouses without installing expensive RF-beacon infrastructure.", "Mining Haulage & Industrial Fleets")
    add_bullet_p(doc, "Eliminates ₹8,000–₹15,000 aftermarket tracking hardware across 10,000 commercial vehicles, delivering an estimated ₹8 to ₹15 Crores in fleet capital savings.", "Economic Impact & Fleet Cost Reduction")
    add_bullet_p(doc, "Provides sovereign navigation continuity resilient to international GNSS jamming, fully compatible with India's indigenous NavIC constellation and PM Gati Shakti.", "National Strategic Sovereignty (Atmanirbhar Bharat)")

    # =========================================================================
    # SECTION 10: UNDERTAKING & STATUTORY SIGNATURE BLOCKS
    # =========================================================================
    add_heading_1(doc, "10. STATUTORY UNDERTAKING & ENDORSEMENT OF AUTHORSHIP")

    add_body_p(
        doc,
        "We, the undersigned authors and faculty supervisor, do hereby solemnly declare that the computer software, "
        "algorithms, architectural designs, and literary technical descriptions contained herein constitute an original intellectual creation "
        "developed jointly by us at Amrutvahini College of Engineering, Sangamner. This work does not infringe upon any existing copyright, "
        "patent, or intellectual property right of any third party. We hereby jointly submit this documentation for copyright registration "
        "under the Indian Copyright Act, 1957."
    )

    doc.add_paragraph() # Spacing

    # Student signatures table (2 rows of 3)
    tbl_sigs_st = doc.add_table(rows=4, cols=3)
    tbl_sigs_st.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_sigs_st.autofit = False
    
    st_widths = [Inches(2.2), Inches(2.2), Inches(2.2)]
    for row in tbl_sigs_st.rows:
        for idx, c in enumerate(row.cells):
            c.width = st_widths[idx]
            set_cell_borders(c)

    # Row 0: space, Row 1: students 1-3
    for c in tbl_sigs_st.rows[0].cells:
        c.paragraphs[0].add_run("\n\n")
    
    st_group_1 = [
        ("Yash Kailas Ekhande", "Team Leader (Lead Developer)\nDept. of E&TC Engineering"),
        ("Abhijeet Dilip Gholap", "Co-Developer (Systems Eng.)\nDept. of E&TC Engineering"),
        ("Ankita Prabhakar Kadu", "Co-Developer (Data Pipeline)\nDept. of E&TC Engineering")
    ]
    for idx, (name, role) in enumerate(st_group_1):
        cell = tbl_sigs_st.cell(1, idx)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        rn = p.add_run(name + "\n")
        rn.font.bold = True
        rn.font.size = Pt(10)
        rd = p.add_run(role)
        rd.font.size = Pt(8.5)
        rd.font.color.rgb = MUTED_GRAY

    # Row 2: space, Row 3: students 4-6
    for c in tbl_sigs_st.rows[2].cells:
        c.paragraphs[0].add_run("\n\n")

    st_group_2 = [
        ("Krushna Sanjay Shinde", "Co-Developer (Dynamics)\nDept. of Automation & Robotics"),
        ("Shreya Gopal Dahale", "Co-Developer (Software)\nDept. of Computer Engineering"),
        ("Kanchan Vijay Jadhav", "Co-Developer (Embedded Test)\nDept. of Automation & Robotics")
    ]
    for idx, (name, role) in enumerate(st_group_2):
        cell = tbl_sigs_st.cell(3, idx)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        rn = p.add_run(name + "\n")
        rn.font.bold = True
        rn.font.size = Pt(10)
        rd = p.add_run(role)
        rd.font.size = Pt(8.5)
        rd.font.color.rgb = MUTED_GRAY

    doc.add_paragraph() # Spacing

    # Institutional Signatories Table
    tbl_inst = doc.add_table(rows=2, cols=3)
    tbl_inst.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_inst.autofit = False

    for row in tbl_inst.rows:
        for idx, c in enumerate(row.cells):
            c.width = st_widths[idx]
            set_cell_borders(c)

    for c in tbl_inst.rows[0].cells:
        c.paragraphs[0].add_run("\n\n\n")

    inst_sigs = [
        ("Mr. V. K. Abhang", "SPOC, Smart India Hackathon\nAmrutvahini College of Engineering"),
        ("Prof. Dr. R. P. Labade", "Faculty Supervisor & Head of Dept.\nDept. of E&TC Engineering"),
        ("Dr. P. R. Baviskar", "Principal\nAmrutvahini College of Engineering")
    ]
    for idx, (name, role) in enumerate(inst_sigs):
        cell = tbl_inst.cell(1, idx)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        rn = p.add_run(name + "\n")
        rn.font.bold = True
        rn.font.size = Pt(10.5)
        rd = p.add_run(role)
        rd.font.size = Pt(9)
        rd.font.color.rgb = MUTED_GRAY

    doc.save(output_docx)
    print(f"Created Comprehensive Copyright Proposal Docx: {output_docx}")

if __name__ == '__main__':
    build_full_document(r'e:\inventor\CopyRight Proposal.docx')
