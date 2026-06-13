# my_routecast

Передача пешего/вело маршрута из **Organic Maps** на часы **Garmin Instinct 3 Tactical
Solar 50 mm** и отрисовка прямо на часах: линия маршрута (heading-up) + псевдо-turn-by-turn
(стрелка следующего поворота, дистанция, вибро) + предупреждение о сходе с маршрута.

Полностью оффлайн. Без Connect IQ Store. Без нативной навигации Garmin — рисуем сами.

## Как этим пользоваться (целевой UX)

1. В Organic Maps построить маршрут → сохранить как трек → **Share → GPX**.
2. Выбрать в «Поделиться» приложение **my_routecast**.
3. На часах заранее открыть виджет **my_routecast**.
4. Маршрут прилетает по BLE и рисуется. Идёшь по линии, на поворотах — стрелка + вибро.

> Шаг 3 (открыть виджет руками) обязателен: Connect IQ не умеет будить приложение на часах
> с телефона мгновенно. Это сознательный компромисс, см. `SPEC.md`.

## Структура

```
my_routecast/
├── README.md          # этот файл
├── SPEC.md            # полное ТЗ
├── CLAUDE.md          # инструкции для Claude Code
├── android/           # companion (Kotlin): Share-таргет → парсер → передача
├── watch/             # Connect IQ виджет (Monkey C): приём → рендер линии + TBT
└── docs/
    └── protocol.md    # схема сообщений phone↔watch
```

## Архитектура (коротко)

```
Organic Maps ──GPX──▶ Android (парс, децимация, манёвры) ──BLE через GCM──▶ Watch widget (рендер)
```

Ограничение, определяющее дизайн: сообщения CIQ маленькие, поэтому маршрут децимируется и
шлётся чанками со stop-and-wait подтверждениями.

## Сборка и установка

### Часы (Connect IQ)
1. VS Code + расширение **Monkey C** от Garmin, скачать SDK через SDK Manager.
2. Device id для Instinct 3 — взять из `<sdk>/bin/devices.xml`.
3. «Build for Device» → получить `.prg`.
4. Подключить часы по USB (монтируются как накопитель) и скопировать `.prg` в `\GARMIN\APPS\`.
5. На часах открыть виджет.

Удалять сайдлоад — через on-device меню Connect IQ или Garmin Express (через телефонное
приложение CIQ нельзя).

### Телефон (Android)
1. Android Studio → собрать APK.
2. `adb install -r app.apk`.
3. Должны быть установлены и спарены: Garmin Connect Mobile + часы.
4. UUID watch-аппа в android-конфиге должен совпадать с `watch/manifest.xml`.

## Статус

Каркас спецификации. Реализация ведётся через Claude Code по `SPEC.md` вертикальными срезами
(см. `CLAUDE.md`).
