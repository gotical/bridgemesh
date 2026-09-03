# Уже опубликовано

BridgeMesh опубликован на GitHub под аккаунтом **gotical**:

- 🔗 **Репозиторий**: https://github.com/gotical/bridgemesh
- 🏷 **Теги**: `v1.0.0`, `v1.1.0`
- 📦 **Релизы**: https://github.com/gotical/bridgemesh/releases
  - [v1.1.0](https://github.com/gotical/bridgemesh/releases/tag/v1.1.0) — APK прикреплён
  - [v1.0.0](https://github.com/gotical/bridgemesh/releases/tag/v1.0.0) — без APK (используйте 1.1.0)

## Скачать готовый APK

Перейдите по ссылке:
https://github.com/gotical/bridgemesh/releases/download/v1.1.0/app-debug.apk

## Клонировать

```bash
git clone https://github.com/gotical/bridgemesh.git
cd bridgemesh
flutter pub get
flutter build apk --debug
```

## Если нужно добавить GitHub Actions workflow

Репозиторий был создан через терминал, у токена нет `workflow`-scope,
поэтому файл `.github/workflows/build-apk.yml` сохранён локально на устройстве
(`~/.bridgemesh-workflow/build-apk.yml`).

Чтобы добавить его в репо вручную:

1. Скопируйте содержимое `.github/workflows/build-apk.yml` из репозитория
   по пути `~/.bridgemesh-workflow/build-apk.yml` (на этом устройстве)
2. На https://github.com/gotical/bridgemesh в Settings → Developer settings
   обновите токен с правами `workflow`, либо
3. Создайте файл через UI: Add file → Create new file →
   `.github/workflows/build-apk.yml` → вставьте содержимое → Commit.

Автосборка на каждый push в `main` и на каждый тег `v*` будет
прикладывать свежий APK к релизу автоматически.
