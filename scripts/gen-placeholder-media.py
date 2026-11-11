#!/usr/bin/env python3
"""生成占位素材：二维码与贡献者头像网格渐变。

用途是把仓库里带真实身份信息的图片换成示意内容，可重复执行、输出确定。

依赖：segno 仅用于 QR 编码，PNG 编码由本文件用标准库自己完成。
安装（exact version + hash 校验，且要求版本发布满 72 小时）：

    python3 -m venv .tools-venv
    printf 'segno==1.6.6 --hash=sha256:28c7d081ed0cf935e0411293a465efd4d500704'
             '072cdb039778a2ab8736190c7\\n' > .tools-venv/requirements-pin.txt
    ./.tools-venv/bin/pip install --no-deps --require-hashes \\
        -r .tools-venv/requirements-pin.txt
"""
import os
import struct
import sys
import zlib

MEDIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                     'entry', 'src', 'main', 'resources', 'base', 'media')

# 占位内容：example.com 由 IANA 保留，不指向任何真实服务；
# 备案查询站是公开政府站点，本身不含主体身份，真正的身份信息在备案号文本里。
QR_ASSETS = [
    ('beian_qr.png', 'https://beian.miit.gov.cn/'),
    ('term_of_service_qr.png', 'https://example.com/dashiell/terms'),
    ('privacy_policy_qr.png', 'https://example.com/dashiell/privacy'),
    ('customer_service_qq_group_qr.png', 'https://example.com/dashiell/community'),
    ('bilibili_API_collect_qr.png', 'https://example.com/dashiell/api-collect'),
]

# 三组示意配色，替代真实头像照片。
AVATAR_ASSETS = [
    ('contributor_6192edb6c6.png', ('#4A90D9', '#7BD3C6', '#2C3E70', '#9BE8C0')),
    ('contributor_854336c250.png', ('#E0665F', '#F2A65A', '#5E3A8C', '#FFD3B6')),
    ('contributor_dc147c8f5d.png', ('#3AA6B9', '#6A4C93', '#8AB4F8', '#252A34')),
]

# 同名换格式后必须移除的旧文件，否则同目录出现重名资源。
LEGACY = ['customer_service_qq_group_qr.jpg', 'contributor_6192edb6c6.jpeg',
          'contributor_854336c250.jpeg', 'contributor_dc147c8f5d.jpeg']

QR_SIZE = 600
AVATAR_SIZE = 512


def rgb(hex_string):
    h = hex_string.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def write_png(name, size, pixel_at):
    """把 pixel_at(x, y) -> (r, g, b) 写成无过滤的 RGB8 PNG。"""
    rows = bytearray()
    for y in range(size):
        rows.append(0)  # 每行的 filter type
        for x in range(size):
            rows.extend(pixel_at(x, y))
    chunks = [
        (b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)),
        (b'IDAT', zlib.compress(bytes(rows), 9)),
        (b'IEND', b''),
    ]
    out = b'\x89PNG\r\n\x1a\n'
    for tag, data in chunks:
        out += struct.pack('>I', len(data)) + tag + data + struct.pack(
            '>I', zlib.crc32(tag + data) & 0xffffffff)
    path = os.path.join(MEDIA, name)
    with open(path, 'wb') as fh:
        fh.write(out)
    return path, len(out)


def draw_qr(name, content):
    import segno
    matrix = [list(row) for row in segno.make(content, error='m').matrix_iter()]
    n = len(matrix)
    module = QR_SIZE // n                      # 整数模块边长，避免半格模糊
    offset = (QR_SIZE - module * n) // 2
    white, black = (255, 255, 255), (0, 0, 0)

    def pixel(x, y):
        mx, my = x - offset, y - offset
        if mx < 0 or my < 0 or mx >= module * n or my >= module * n:
            return white                        # 外围补白，保证严格 600x600
        return black if matrix[my // module][mx // module] else white

    return write_png(name, QR_SIZE, pixel)


def draw_avatar(name, corners):
    tl, tr, bl, br = (rgb(c) for c in corners)

    def smooth(t):                               # smoothstep，让渐变不带硬对角棱线
        return t * t * (3 - 2 * t)

    def mix(a, b, t):
        return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

    def pixel(x, y):
        u, v = smooth(x / (AVATAR_SIZE - 1)), smooth(y / (AVATAR_SIZE - 1))
        return mix(mix(tl, tr, u), mix(bl, br, u), v)

    return write_png(name, AVATAR_SIZE, pixel)


def main():
    try:
        import segno  # noqa: F401
    except ImportError:
        print('缺少 segno。按文件头部的 pin + hash 方式安装后重试。', file=sys.stderr)
        return 2
    os.makedirs(MEDIA, exist_ok=True)
    for name in QR_ASSETS:
        path, size = draw_qr(*name)
        print('QR  %5d B  %s  <- %s' % (size, os.path.basename(path), name[1]))
    for spec in AVATAR_ASSETS:
        path, size = draw_avatar(*spec)
        print('渐变 %5d B  %s' % (size, os.path.basename(path)))
    for legacy in LEGACY:
        p = os.path.join(MEDIA, legacy)
        if os.path.exists(p):
            os.remove(p)
            print('移除旧素材 %s' % legacy)
    return 0


if __name__ == '__main__':
    sys.exit(main())
