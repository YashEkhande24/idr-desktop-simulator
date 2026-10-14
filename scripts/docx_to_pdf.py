import sys
import os
import subprocess

def convert_docx_to_pdf(docx_path, pdf_path):
    docx_path = os.path.abspath(docx_path)
    pdf_path = os.path.abspath(pdf_path)
    
    ps_script = f"""
$word = New-Object -ComObject Word.Application
$word.Visible = $false
try {{
    $doc = $word.Documents.Open('{docx_path}')
    $doc.SaveAs([ref]'{pdf_path}', [ref]17)
    $doc.Close([ref]0)
    Write-Host "SUCCESS"
}} catch {{
    Write-Error $_
    exit 1
}} finally {{
    $word.Quit()
}}
"""
    script_file = os.path.join(os.environ.get('TEMP', '.'), 'temp_docx2pdf.ps1')
    with open(script_file, 'w', encoding='utf-8') as f:
        f.write(ps_script)
        
    res = subprocess.run(['powershell', '-ExecutionPolicy', 'Bypass', '-File', script_file], capture_output=True, text=True)
    if 'SUCCESS' in res.stdout:
        print(f"Successfully converted {docx_path} -> {pdf_path}")
        return True
    else:
        print(f"Conversion failed:\nSTDOUT: {res.stdout}\nSTDERR: {res.stderr}")
        return False

def convert_to_doc(docx_path, doc_path):
    docx_path = os.path.abspath(docx_path)
    doc_path = os.path.abspath(doc_path)
    
    ps_script = f"""
$word = New-Object -ComObject Word.Application
$word.Visible = $false
try {{
    $d = $word.Documents.Open('{docx_path}')
    $d.SaveAs([ref]'{doc_path}', [ref]0)
    $d.Close([ref]0)
    Write-Host "SUCCESS DOC"
}} catch {{
    Write-Error $_
    exit 1
}} finally {{
    $word.Quit()
}}
"""
    script_file = os.path.join(os.environ.get('TEMP', '.'), 'temp_savedoc.ps1')
    with open(script_file, 'w', encoding='utf-8') as f:
        f.write(ps_script)
        
    res = subprocess.run(['powershell', '-ExecutionPolicy', 'Bypass', '-File', script_file], capture_output=True, text=True)
    if 'SUCCESS DOC' in res.stdout:
        print(f"Successfully converted {docx_path} -> {doc_path}")
        return True
    else:
        print(f"Conversion failed:\nSTDOUT: {res.stdout}\nSTDERR: {res.stderr}")
        return False

if __name__ == '__main__':
    if len(sys.argv) > 2:
        if sys.argv[2].lower().endswith('.doc'):
            convert_to_doc(sys.argv[1], sys.argv[2])
        else:
            convert_docx_to_pdf(sys.argv[1], sys.argv[2])
    else:
        print("Usage: python docx_to_pdf.py <input.docx> <output.pdf or output.doc>")

