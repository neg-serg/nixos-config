# pyright: reportMissingImports=false
from datetime import datetime
from kitty.boss import get_boss
from kitty.fast_data_types import (
    Screen,
    add_timer,
    current_focused_os_window_id,
    get_options,
)
from kitty.utils import color_as_int
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    Formatter,
    TabBarData,
    as_rgb,
    draw_attributed_string,
    draw_title,
)

opts = get_options()
icon_fg = as_rgb(color_as_int(opts.color24))
icon_bg = as_rgb(color_as_int(opts.color0))
bat_text_color = as_rgb(color_as_int(opts.color15))
clock_color = as_rgb(color_as_int(opts.color15))
date_color = as_rgb(color_as_int(opts.color8))
SEPARATOR_SYMBOL, SOFT_SEPARATOR_SYMBOL = ("", "")
RIGHT_MARGIN = 1
REFRESH_TIME = 1
ICON = ""
UNFOCUSED_ACTIVE_TITLE_TEMPLATE = (
    "   {index}:{f'{title[:6]}…{title[-6:]}' if len(title) > 25 else title}"
    "{' []' if layout_name == 'stack' else ''} "
)


def _draw_icon(screen: Screen, index: int) -> int:
    if index != 1:
        return 0
    fg, bg = screen.cursor.fg, screen.cursor.bg
    screen.cursor.fg = icon_fg
    screen.cursor.bg = icon_bg
    screen.draw(ICON)
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.x = len(ICON)
    return screen.cursor.x


def _draw_left_status(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    if screen.cursor.x >= screen.columns - right_status_length:
        return screen.cursor.x
    tab_bg = screen.cursor.bg
    tab_fg = screen.cursor.fg
    default_bg = as_rgb(int(draw_data.default_bg))
    if extra_data.next_tab:
        next_tab_bg = as_rgb(draw_data.tab_bg(extra_data.next_tab))
        needs_soft_separator = next_tab_bg == tab_bg
    else:
        next_tab_bg = default_bg
        needs_soft_separator = False
    if screen.cursor.x <= len(ICON):
        screen.cursor.x = len(ICON)
    screen.draw("")
    screen.cursor.bg = tab_bg
    draw_title(draw_data, screen, tab, index)
    end = screen.cursor.x
    return end


def _draw_right_status(screen: Screen, is_last: bool) -> int:
    if not is_last:
        return 0
    draw_attributed_string(Formatter.reset, screen)
    screen.cursor.x = screen.columns - right_status_length
    screen.cursor.fg = 0
    screen.cursor.bg = 0
    return screen.cursor.x


def _redraw_tab_bar(_):
    tm = get_boss().active_tab_manager
    if tm is not None:
        tm.mark_tab_bar_dirty()


timer_id = None
right_status_length = -1


def _is_active_in_inactive_window(draw_data: DrawData, tab: TabBarData) -> bool:
    if not tab.is_active:
        return False
    try:
        focused_id = current_focused_os_window_id()
    except Exception:
        return False
    if not focused_id:
        return False
    return draw_data.os_window_id != focused_id


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    global timer_id
    global right_status_length
    if timer_id is None:
        timer_id = add_timer(_redraw_tab_bar, REFRESH_TIME, True)
    draw_data_for_tab = draw_data
    if _is_active_in_inactive_window(draw_data, tab):
        draw_data_for_tab = draw_data_for_tab._replace(
            title_template=UNFOCUSED_ACTIVE_TITLE_TEMPLATE,
            active_title_template=None,
        )
        screen.cursor.bold = False
        screen.cursor.italic = False
        screen.cursor.fg = as_rgb(color_as_int(draw_data.active_fg))
        screen.cursor.bg = as_rgb(color_as_int(draw_data.active_bg))
    clock = datetime.now().strftime(" %H:%M")
    date = datetime.now().strftime(" %d.%m.%Y")
    right_status_length = RIGHT_MARGIN

    _draw_icon(screen, index)
    _draw_left_status(
        draw_data_for_tab,
        screen,
        tab,
        before,
        max_title_length,
        index,
        is_last,
        extra_data,
    )
    _draw_right_status(
        screen,
        is_last,
    )
    return screen.cursor.x
