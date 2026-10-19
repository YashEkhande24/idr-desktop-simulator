"""
create_code_zip.py
==================
Packages all source code, tests, and build configurations into a clean zip archive,
excluding all binary ML models (.pth, .onnx, .pt, .npz), compiled libraries (.so, .a, .o),
datasets (.csv), media (.png, .jpg, .mp4), documents (.pdf, .docx, .pptx), and cache/build directories.
"""

import os
import zipfile

CODE_EXTENSIONS = {
    # Dart / Flutter
    '.dart',
    # Python
    '.py',
    # C / C++ / Headers
    '.cpp', '.hpp', '.h', '.c', '.cc', '.cxx',
    # Kotlin / Java
    '.kt', '.java',
    # Web
    '.js', '.html', '.css',
    # Shell / Batch
    '.bat', '.sh', '.ps1',
    # Build / Project / Config files
    '.yaml', '.yml', '.cmake', '.rc', '.manifest', '.properties',
    '.xml', '.json', '.txt', '.md', '.tex'
}

SPECIAL_CODE_FILES = {
    'CMakeLists.txt', 'Dockerfile', 'Makefile', '.gitignore',
    'gradlew', 'gradlew.bat', 'pubspec.lock', 'analysis_options.yaml'
}

EXCLUDE_DIRS = {
    '.git', '.idea', '.dart_tool', '.pytest_cache', '__pycache__',
    'build', '.gradle', '.cxx', 'node_modules', '.history',
    'build_armeabi_v7a', 'build_x86_64', '.firebase', 'experiments',
    '.kilo', 'eval_plots', 'sample_data', 'datasets', 'IO-VNBD',
    'excluded_datasets', 'coverage', '.metadata'
}

EXCLUDE_EXTENSIONS = {
    '.zip', '.pdf', '.docx', '.doc', '.pptx', '.mp4', '.png', '.jpg', '.jpeg',
    '.ico', '.webp', '.so', '.a', '.o', '.bin', '.ninja', '.ninja_deps', '.ninja_log',
    '.pth', '.onnx', '.pt', '.npz', '.apk', '.aab', '.jar', '.pyc', '.class',
    '.csv', '.log', '.aux', '.cache', '.check_cache', '.iml'
}

EXCLUDE_FILES = {
    'local.properties', '.flutter-plugins-dependencies', 'training.log',
    'training_log.csv', 'training_log.txt'
}

def should_include(rel_path):
    parts = rel_path.replace('\\', '/').split('/')
    filename = parts[-1]
    ext = os.path.splitext(filename)[1].lower()
    
    for p in parts[:-1]:
        if p in EXCLUDE_DIRS or p.startswith('.cxx') or p.startswith('build') or p.startswith('.gradle'):
            return False
            
    if filename in EXCLUDE_FILES or filename.endswith('local.properties'):
        return False
    if ext in EXCLUDE_EXTENSIONS:
        return False
        
    if ext in CODE_EXTENSIONS or filename in SPECIAL_CODE_FILES:
        return True
    return False

def make_code_zip(output_zip='code.zip', root_dir='.'):
    matched = []
    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS and not d.startswith('.cxx') and not d.startswith('build') and not d.startswith('.gradle')]
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), root_dir).replace('\\', '/')
            if should_include(rel):
                matched.append(rel)

    matched.sort()
    out_path = os.path.join(root_dir, output_zip)
    with zipfile.ZipFile(out_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for rel_path in matched:
            full_path = os.path.join(root_dir, rel_path)
            zf.write(full_path, rel_path)

    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f"Successfully generated '{output_zip}': {len(matched)} files ({size_mb:.2f} MB)")
    return out_path

if __name__ == '__main__':
    make_code_zip()
