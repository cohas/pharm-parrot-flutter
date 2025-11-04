import re

with open('lib/screens/main_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1) await _speak 라인 제거
lines = content.split('\n')
new_lines = []
for line in lines:
    # _speak를 호출하는 라인 스킵
    if "await _speak(" in line and ("중복" in line or "바코드" in line or "개" in line):
        print(f"Removing: {line.strip()}")
        continue
    new_lines.append(line)

content = '\n'.join(new_lines)

# 2) 현재 로직 수정
# (checkedNow + delta).round() → checkedNow.round() + affected
content = content.replace(
    'max(0, min(32767, checkedNow.round() + affected))',
    'max(0, min(32767, checkedNow.round() + affected))'
)  # 이미 수정됨

with open('lib/screens/main_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ File updated successfully")
