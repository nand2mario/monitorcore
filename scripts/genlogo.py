#!/usr/bin/python3

from PIL import Image
from PIL import ImageFont
from PIL import ImageDraw

S=8
logocolor = (30, 150, 220)
fontname = 'RussoOne-Regular.ttf'

def draw_logo():
    image = Image.new('RGB', (256*S, 256*S), color = (0, 0, 0))
    fnt = ImageFont.truetype(fontname, 15*S)
    usr = ImageDraw.Draw(image)

    usr.text((2*S, 0), "SMSTang", fill=logocolor, font=fnt)

    # image.save('logo.png')
    left=13
    top=25
    image = image.crop((left, top, left+72*S, top+14*S))
    return image

def get_logo_data(image):
    #################################################
    # Convert image to grayscale
    gray = image.convert('L')

    # Initialize empty list for logo data
    logo_data = []

    # Set threshold to half of S*S
    threshold = (S * S) // 2

    # Process each 14x72 grid
    for y in range(0, 14*S, S):
        row = ""
        for x in range(0, 72*S, S):
            # Count white pixels in SxS block
            white_count = 0
            for i in range(S):
                for j in range(S):
                    if gray.getpixel((x + j, y + i)) > 50:
                        white_count += 1
            # Append 1 or 0 based on threshold
            if white_count > threshold:
                row += "1"
            else:
                row += "0"
        logo_data.append(row)
    return logo_data

def print_hex(logo_data):
    r = []

    for i in range(126):
        j = i % 9
        s = logo_data[i // 9][j*8 : j*8+8]
        b = 0
        for k in range(8):
            if s[k] == '1':
                b += 1 << k
        # print("{} -> {:02X}".format(s, b))
        r.append(b)

    assert(len(r) == 126)

    r.append(0)
    r.append(0)

    for i in range(4):
        off = i * 32
        print("defparam dpb_inst_0.INIT_RAM_{:02X} = 256'h".format(0x1C+i), end='')
        for j in range(31, -1, -1):     # 31, 30, ...
            print("{:02X}".format(r[off+j]), end='')
        print()
            

def save_preview(image, filename):
    #######################################################
    # Output logo.png for preview
    usr = ImageDraw.Draw(image)
    gridcolor = (50, 50, 50)
    coordcolor = (130, 130, 130)

    # Draw vertical grid lines
    for i in range(0, 72*S, S):
        usr.line((i, 0, i, 14*S), fill=gridcolor, width=1)

    # Draw horizontal grid lines  
    for i in range(0, 14*S, S):
        usr.line((0, i, 72*S, i), fill=gridcolor, width=1)

    # Draw numbers in first row
    fnt2 = ImageFont.truetype(fontname, S)
    for i in range(72):
        x = i * S + 2
        y = 0
        usr.text((x, y), str(i % 10), fill=coordcolor, font=fnt2)

    # Draw numbers in first column
    for i in range(14):
        x = 2
        y = i * S
        usr.text((x, y), str(i % 10), fill=coordcolor, font=fnt2)

    # Draw BGR5 color value in bottom right corner
    bgr5 = (logocolor[2] >> 3) << 10 | (logocolor[1] >> 3) << 5 | (logocolor[0] >> 3)
    x = 72*S - 100
    y = 14*S - S
    usr.text((x, y), f"BGR5: {bgr5:015b}", fill=coordcolor, font=fnt2)

    image.save(filename)
    # image.crop((0, 10, 72*S, 14*S)).resize((72,14)).convert('1').save('logo.png')


image = draw_logo()

logo_data = get_logo_data(image)

# Print logo data: 72*14
for row in logo_data:
    print(row)

# Print hex values for `iosys/gowin_dpb_menu.v`
print("\nCut and paste the following into `iosys/gowin_dpb_menu.v`:\n")
print_hex(logo_data)

print("\nA preview of the logo is saved as `logo.png`.")
save_preview(image, 'logo.png')
