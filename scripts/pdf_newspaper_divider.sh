python3 -c "
from pypdf import PdfReader, PdfWriter
import os

src = '/home/dude/Documents/GitHub/YourStockForecast/frontend/hugo-site/static/pdf/1929-10-28-time.pdf'
out_dir = '/home/dude/Documents/GitHub/YourStockForecast/frontend/hugo-site/static/pdf'

reader = PdfReader(src)
print(f'Splitting {len(reader.pages)} pages...')

for i, page in enumerate(reader.pages):
    writer = PdfWriter()
    writer.add_page(page)
    out_path = os.path.join(out_dir, f'1929-10-28-time-{i+1}.pdf')
    with open(out_path, 'wb') as f:
        writer.write(f)
    print(f'  wrote {os.path.basename(out_path)}')

print('Done.')
"
