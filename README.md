# PharmParrot Flutter (Android)

이 폴더는 기존 C# WPF 앱(PharmParrot)을 Flutter로 재구현한 코드입니다.

중요 사항
- 윈도우 전용 기능(시리얼/COM, 바코드 카메라, 다국어)은 제외했습니다.
- Supabase 연동으로 처방 헤더/처방 상세 조회 및 완료 처리만 동일하게 동작하도록 구현했습니다.
- Android 사용을 중심으로 레이아웃을 단순화했습니다.

필요사항
- Flutter SDK 설치 및 Android 개발 환경(ADB, Android SDK) 준비
- Supabase URL/Anon Key 설정: `lib/config.dart`의 상수 또는 `--dart-define` 사용

프로젝트 생성과 실행 방법
1) Flutter 기본 스캐폴드 생성 (플랫폼 폴더 포함)
   - 새 앱으로 만들고 이 `lib/`만 교체하는 방법을 권장합니다.
   - 예시:
     flutter create pharm_parrot_flutter
     cd pharm_parrot_flutter
     # 아래 단계에서 `lib/` 내용을 덮어쓰기

2) 이 저장소의 `flutter/lib`를 생성된 앱의 `lib`로 복사하고, `pubspec.yaml`의 dependencies를 참고해 업데이트합니다.

3) Supabase 설정
   - 방법 A: `lib/config.dart` 내 상수로 설정
   - 방법 B: 빌드 시 `--dart-define` 사용
     flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

4) 실행
   flutter pub get
   flutter run -d android

주요 화면/기능
- 날짜/이름/환자번호로 RxHead 조회
- RxHead 선택 시 RxRecipe 조회 및 분할(Seperate)별 총량 계산
- 처방 완료 버튼 (update_rxhead_complete)
- RxRecipe 항목 탭 → 편집 다이얼로그(ATC/위치/메모/용량 등) 저장

제외된 기능
- 시리얼(COM) 바코드, 카메라 미리보기/스캔, 다국어 UI

구조
- lib/
  - main.dart: 앱 진입점 및 Supabase 초기화
  - config.dart: Supabase 설정
  - services/supabase_service.dart: RPC 래퍼
  - screens/main_screen.dart: 메인 UI/로직
  - widgets/patient_drug_dialog.dart: 처방 상세 편집 다이얼로그

알림
- 실제 빌드/배포 시 Supabase 키는 안전한 방식으로 주입하세요.
