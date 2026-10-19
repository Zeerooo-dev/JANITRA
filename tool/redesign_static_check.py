"""Conservative syntax-bracket check (not a replacement for `flutter analyze`)."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent / 'lib'
files = list(root.rglob('*.dart'))
for path in files:
    src = path.read_text()
    stack, state, quote, i = [], 'code', '', 0
    while i < len(src):
        c = src[i]
        n = src[i + 1] if i + 1 < len(src) else ''
        if state == 'code':
            if c == '/' and n == '/': state = 'line'; i += 2; continue
            if c == '/' and n == '*': state = 'block'; i += 2; continue
            if c in ("'", '"'):
                quote = c
                if src[i:i + 3] == c * 3: state = 'triple'; i += 3; continue
                state = 'string'; i += 1; continue
            if c in '({[': stack.append(c)
            elif c in ')}]':
                assert stack and stack.pop() == {')': '(', '}': '{', ']': '['}[c], str(path)
        elif state == 'line':
            if c == '\n': state = 'code'
        elif state == 'block':
            if c == '*' and n == '/': state = 'code'; i += 2; continue
        elif state == 'string':
            if c == '\\': i += 2; continue
            if c == quote: state = 'code'
        elif state == 'triple':
            if src[i:i + 3] == quote * 3: state = 'code'; i += 3; continue
        i += 1
    assert not stack and state in ('code', 'line'), str(path)
print(f'Structural check passed: {len(files)} Dart files')
