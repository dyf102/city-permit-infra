import os
import re
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib import colors

def process_markdown_line(line):
    # Escape special characters for ReportLab XML
    line = line.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    
    # Re-enable basic tags after escaping
    line = line.replace('&lt;b&gt;', '<b>').replace('&lt;/b&gt;', '</b>')
    line = line.replace('&lt;i&gt;', '<i>').replace('&lt;/i&gt;', '</i>')
    line = line.replace('&lt;br/&gt;', '<br/>')

    # Handle Bold: **text**
    line = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', line)
    
    # Handle Inline Code: `text`
    line = re.sub(r'`(.*?)`', r'<font face="Courier">\1</font>', line)
    
    # Handle bullet points
    if line.startswith('- ') or line.startswith('* '):
        line = f"&bull; {line[2:]}"
        
    return line

def generate_pdf(input_md_path, output_pdf_path, title):
    doc = SimpleDocTemplate(output_pdf_path, pagesize=letter,
                            rightMargin=72, leftMargin=72,
                            topMargin=72, bottomMargin=72)
    styles = getSampleStyleSheet()
    
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Title'],
        fontSize=24,
        spaceAfter=30,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold'
    )
    
    h1_style = ParagraphStyle(
        'CustomH1',
        parent=styles['Heading1'],
        fontSize=18,
        spaceBefore=20,
        spaceAfter=12,
        color=colors.HexColor("#2E5077"),
        fontName='Helvetica-Bold'
    )
    
    h2_style = ParagraphStyle(
        'CustomH2',
        parent=styles['Heading2'],
        fontSize=14,
        spaceBefore=15,
        spaceAfter=10,
        color=colors.HexColor("#4DA1A9"),
        fontName='Helvetica-Bold'
    )

    body_style = styles['Normal']
    body_style.fontSize = 11
    body_style.leading = 14
    body_style.spaceAfter = 10
    body_style.fontName = 'Helvetica'

    story = []
    story.append(Paragraph(title, title_style))
    story.append(Spacer(1, 12))

    if not os.path.exists(input_md_path):
        return

    with open(input_md_path, 'r') as f:
        content = f.read()

    # Split by lines but handle basic blocks
    lines = content.split('\n')
    for line in lines:
        stripped = line.strip()
        if not stripped:
            story.append(Spacer(1, 6))
            continue
            
        if stripped.startswith('# '):
            story.append(Paragraph(process_markdown_line(stripped[2:]), h1_style))
        elif stripped.startswith('## '):
            story.append(Paragraph(process_markdown_line(stripped[3:]), h2_style))
        elif stripped.startswith('### '):
            story.append(Paragraph(process_markdown_line(stripped[4:]), h2_style))
        else:
            story.append(Paragraph(process_markdown_line(line), body_style))

    doc.build(story)
    print(f"PDF generated: {output_pdf_path}")

if __name__ == "__main__":
    generate_pdf("AWS_CREDITS_PLAN.md", "AWS_CREDITS_PLAN.pdf", "AWS Credits Application Plan")
    generate_pdf("DOWNGRADE_PLAN.md", "DOWNGRADE_PLAN.pdf", "Infrastructure Downgrade Plan")
