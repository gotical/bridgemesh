# Как опубликовать на GitHub

У меня нет доступа к твоему GitHub-аккаунту, поэтому публикацию придётся
сделать тебе. Ниже — пошаговая инструкция.

## 1. Создай репозиторий на GitHub

Перейди на <https://github.com/new> и создай новый **публичный** репозиторий:

- **Repository name**: `bridgemesh`
- **Description**: `BridgeMesh — общение без интернета и сотовой связи (mesh-сеть через Bluetooth и Wi-Fi Direct)`
- **Public** или **Private** — на твой выбор
- НЕ ставь галочки README / .gitignore / LICENSE (они уже есть)

После создания скопируй URL — выглядит так:
`https://github.com/<твой-username>/bridgemesh.git`

## 2. Запуш всё одной командой

```bash
cd /data/data/com.termux/files/home/bridgemesh

git remote add origin https://github.com/<твой-username>/bridgemesh.git
git push -u origin main
git push origin --tags    # запушит все теги (v1.0.0 и v1.1.0)
```

Если удалённый репозиторий уже был с v1.0.0:

```bash
git remote add origin https://github.com/<твой-username>/bridgemesh.git
git push -u origin main
git push origin v1.1.0
```

## 3. Создай релизы

На GitHub открой **Releases** → **Draft a new release**.

### Тег v1.0.0

- **Tag**: `v1.0.0`
- **Title**: `BridgeMesh 1.0.0`
- **Attach**: `~/bridgemesh/BridgeMesh-1.0.0-debug.apk`

### Тег v1.1.0

- **Tag**: `v1.1.0`
- **Title**: `BridgeMesh 1.1.0 — сохранение данных, фоновый режим, эконом`
- **Attach**: `~/bridgemesh/BridgeMesh-1.1.0-debug.apk`
- **Description** (можно скопировать из CHANGELOG.md):

```
- Сохранение данных между запусками.
- Фоновая работа через foreground-сервис.
- Режим энергосбережения «Отключиться (эконом)».
- Новая иконка приложения.
- Bottom Navigation Bar выровнен и центрирован.
- Полностью на русском, без жаргона.
- Исправлены overflow ошибки интерфейса.
```

## 4. CI (опционально)

Файл `.github/workflows/build-apk.yml` уже лежит в репозитории. Чтобы
включить автосборку:

- Settings → Actions → General → Allow all actions → Save
- После `git push` Actions автоматически соберёт APK и положит в артефакты
- При пуше тега `v*` — приложит APK к релизу автоматически

## Содержимое репозитория

```
bridgemesh/
├── README.md                       # Описание, разрешения, как собрать
├── CHANGELOG.md                    # История изменений (1.0.0, 1.1.0)
├── LICENSE                         # MIT
├── PUBLISH.md                      # Эта инструкция
├── .github/workflows/build-apk.yml # Автосборка APK
├── android/                        # Android-проект (Gradle KTS, Kotlin)
├── lib/                            # Dart-код (Flutter)
├── Bridgemesh-1.0.0-debug.apk      # Сборка 1.0.0
└── BridgeMesh-1.1.0-debug.apk      # Сборка 1.1.0
```
