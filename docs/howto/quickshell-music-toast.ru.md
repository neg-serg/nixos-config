# Медиа-тост Quickshell: как делать правильно

Выстрадано на odin. Правила ниже — что нельзя повторять и как делать, чтобы тост был компактным,
прижатым к панели и стабильным.

## Файлы

- files/quickshell/Widgets/SidePanel/MusicPopup.qml — окно/карточка тоста.
- files/quickshell/Widgets/SidePanel/Music.qml — содержимое (обложка, метаданные, прогресс, кнопки).
- files/quickshell/Components/IPhoneSpectrum.qml — анализатор (bars/led/wave).
- files/quickshell/Bar/Modules/Media.qml — медиа-капсула в баре + мини-превью.
- files/quickshell/Settings/Settings.qml — дефолты настроек.

## 1. Позиция карточки — низ карточки = панель

- Окно MusicPopup — полноэкранный WlrLayershell; карточка cardBox заякорена вниз-вправо.
- Нижний отступ — вплотную к панели (около 1px). В computeBottomMargin() возвращать маленькую
  константу, а не baseMargin() + большой gap: function computeBottomMargin() { return Math.max(0,
  Math.round(1 * Theme.scale(Screen))); }
- Большой воздух \_bottomGapPx (56 и т.п.) НЕ добавлять — он уводил карточку от панели.
- Правочный отступ можно оставить baseMargin().

## 2. Высота карточки — по контенту, не по настройке

- НЕ форсить высоту карточки из musicPopupHeight — карточка получалась высокой, а контент висел
  сверху с пустотой снизу.
- Music-виджет не должен получать жёсткий height: musicHeightPx — пусть растёт по своему
  implicitHeight (по контенту).
- computeCardHeight() берёт реальную высоту контента musicWidget.implicitHeight, а musicPopupHeight
  — только как fallback.
- После раскладки пересчитать высоту (карточка обнимает контент стабильно): Qt.callLater(function()
  { toast.cardHeightPx = toast.computeCardHeight(); });
- Кап ограничивать реальным экраном, НЕ высотой самого окна: раньше ScreenUtil.height(sidebarPopup)
  давал петлю (окно → cap → карточка), и карточка вообще не росла в высоту.

## 3. Контент внутри карточки

- playerUI в Music.qml: anchors.bottom: parent.bottom — контент прижат к низу карточки (обложка
  оказывается у панели). НЕ центрировать по вертикали.
- verticalItemAlignment на ColumnLayout не существует — даёт warning 'Cannot assign to non-existent
  property'. Не использовать.
- Обложка и колонка метаданных: Layout.alignment: Qt.AlignBottom, чтобы обложка стояла на нижней
  кромке карточки.

## 4. Анализатор: режимы, цвета, разделители

- spectrumMode: bars | led | wave — это РАЗНЫЕ реализации (полосы / LED-сегменты / плавная волна).
  Пресеты \*AnalyserStyle — только палитры цвета поверх реализации.
- spectrumColor (hex) — переопределение цвета поверх палитры/обложки; пусто = пресет/акцент.
- Мини-превью в баре (Media.qml): плоское, цвет обложки, тонкое (barGap: 4, minBarWidth: 1), без
  glow/threeD.
- Разделитель названия трека — «—» (mediaTitleSeparator), НЕ заменять на слэш. Слэш времени cur /
  total уже красится акцентом через Rich.sepSpan(accentCss, '/') — его только красить, символ не
  менять.

## 5. Скраб-бар (полоса прогресса)

- Тонкая: musicPopupProgressHeight около 3 (логических px).
- Заливка и bloom — цвет обложки (акцент), не серый; трек-волосок тоже тонируется акцентом (низкая
  альфа).
- Свечение — вертикальный bloom: заякорить к низу линии и растить вверх (чтобы не наезжало на
  название снизу), высота около 0.3 высоты полосы.
- Bloom не должен быть по бокам и не должен зависеть от длины/ширины заливки (при растягивании
  карточки эффект не расползается).

## Настройки (Settings.json)

- musicPopupWidth, musicPopupHeight (высота теперь только fallback), musicPopupEdgeMargin,
  musicPopupProgressHeight.
- spectrumMode, spectrumColor, toastAnalyserStyle, barAnalyserStyle, mediaTitleSeparator.
- spectrumMinHz/MaxHz/ColorMinHz/ColorMaxHz — частотная полоса и подсветка.
