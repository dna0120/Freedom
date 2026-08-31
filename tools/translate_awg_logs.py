#!/usr/bin/env python3
"""Translate Russian user-facing log strings in merged AWG scripts to English."""
from pathlib import Path

REPLACEMENTS = [
    (
        'log_warn "Файл $init изменён позже $live, и параметры обфускации в них расходятся: ${drift% }"',
        'log_warn "File $init was modified after $live and obfuscation parameters differ: ${drift% }"',
    ),
    (
        'log_warn "Действуют значения из $live - после установки он единственный источник этих параметров. Если вы правили их в $init, до клиентов правка не дойдёт: меняйте секцию [Interface] в $live, затем перезапустите awg-quick@awg0 и выполните regen нужных клиентов."',
        'log_warn "Values from $live are in effect - after install it is the sole source for these parameters. Edits in $init will not reach clients: change [Interface] in $live, then restart awg-quick@awg0 and regen affected clients."',
    ),
    (
        "(( n > 1 )) && log_warn \"'${key}' у клиента '${name}' задан ${n} строками - значения объединены в одну.\"",
        "(( n > 1 )) && log_warn \"Client '${name}' '${key}' was set in ${n} lines - values merged into one.\"",
    ),
    (
        'log_warn "Интерфейс awg0 будет перезапущен - соединения всех клиентов прервутся на несколько секунд."',
        'log_warn "Interface awg0 will be restarted - all client connections will drop for a few seconds."',
    ),
    (
        'log_warn "ВНИМАНИЕ: похоже, вы подключены к серверу ЧЕРЕЗ этот же VPN."',
        'log_warn "WARNING: you appear to be connected to this server THROUGH this VPN."',
    ),
    (
        'log_warn "  Адрес вашей сессии $addr входит в подсеть туннеля ${subnet},"',
        'log_warn "  Your session address $addr is inside tunnel subnet ${subnet},"',
    ),
    (
        'log_warn "  значит после перезапуска текущее подключение оборвётся."',
        'log_warn "  so the current connection will drop after restart."',
    ),
    (
        'log_warn "  Если доступ не вернётся сам - заходите через консоль или VNC в панели"',
        'log_warn "  If access does not return on its own, use the provider console or VNC panel"',
    ),
    (
        'log_warn "  вашего провайдера: она работает в обход VPN."',
        'log_warn "  - it works outside the VPN."',
    ),
    (
        'log_debug "Сессия идёт не через туннель (адрес $addr) - доступ к серверу не пострадает."',
        'log_debug "Session is not via the tunnel (address $addr) - server access will not be affected."',
    ),
    (
        'log_warn "  Если вы подключены к серверу ЧЕРЕЗ этот VPN, вы потеряете доступ."',
        'log_warn "  If you are connected to this server THROUGH this VPN, you will lose access."',
    ),
    (
        'log_warn "  Запасной путь на такой случай - консоль или VNC в панели провайдера."',
        'log_warn "  Fallback: provider console or VNC panel."',
    ),
    (
        'log_warn "Не удалось записать снимок параметров интерфейса ($state) - проверьте место на диске и права."',
        'log_warn "Failed to write interface parameter snapshot ($state) - check disk space and permissions."',
    ),
    (
        'log_warn "Не удалось заменить снимок параметров интерфейса ($state) - проверьте место на диске и права."',
        'log_warn "Failed to replace interface parameter snapshot ($state) - check disk space and permissions."',
    ),
    (
        'log "Перезапуск сервиса (apply-mode=restart)..."',
        'log "Restarting service (apply-mode=restart)..."',
    ),
    (
        'log_warn "Ошибка перезапуска."',
        'log_warn "Service restart error."',
    ),
    (
        'log_warn "Из секции [Interface] убрано: ${removed}."',
        'log_warn "Removed from [Interface]: ${removed}."',
    ),
    (
        'log_warn "  syncconf такие параметры НЕ снимает - на живом интерфейсе они останутся."',
        'log_warn "  syncconf does NOT remove such parameters - they remain on the live interface."',
    ),
    (
        'log_warn "  Чтобы снятие вступило в силу, интерфейс надо пересоздать:"',
        'log_warn "  To apply removal, recreate the interface:"',
    ),
    (
        'log_warn "  Это оборвёт соединения всех клиентов на несколько секунд, поэтому"',
        'log_warn "  This will drop all client connections for a few seconds, so"',
    ),
    (
        'log_warn "  сами мы этого не делаем. Если вы уже перезапускали сервис вручную,"',
        'log_warn "  we do not do this automatically. If you already restarted manually,"',
    ),
    (
        'log_warn "  предупреждение можно игнорировать: после успешного применения снимок"',
        'log_warn "  you may ignore this warning: after a successful apply the snapshot"',
    ),
    (
        'log_warn "  обновится, и на следующих запусках этой строки не будет."',
        'log_warn "  will update and this message will not appear on the next run."',
    ),
    (
        'log_warn "awg-quick strip не удался или timeout, использую полный перезапуск."',
        'log_warn "awg-quick strip failed or timed out, falling back to full restart."',
    ),
    (
        'log_warn "awg syncconf не удался или timeout, использую полный перезапуск."',
        'log_warn "awg syncconf failed or timed out, falling back to full restart."',
    ),
    (
        'log_debug "Конфигурация применена (syncconf)."',
        'log_debug "Config applied (syncconf)."',
    ),
    (
        '[[ -n "$allowed_ips" ]] || { log_warn "AllowedIPs не прочитан из \'$conf_file\' - в ссылку уйдёт полный туннель."; allowed_ips="0.0.0.0/0"; }',
        '[[ -n "$allowed_ips" ]] || { log_warn "AllowedIPs not read from \'$conf_file\' - full tunnel will be used in the link."; allowed_ips="0.0.0.0/0"; }',
    ),
    # manage_amneziawg.sh
    (
        'log "Восстановление завершено."',
        'log "Restore completed."',
    ),
    (
        'log_error "awg_common.sh устарела: нет awg_normalize_csv. Обнови обе половины под одну версию."',
        'log_error "awg_common.sh is outdated: missing awg_normalize_csv. Update both halves to the same version."',
    ),
    (
        'log_error "Нормализация \'$param\' дала пустое значение - правка отменена."',
        'log_error "Normalizing \'$param\' produced an empty value - change aborted."',
    ),
    (
        'log "Значение приведено к виду: $value"',
        'log "Value normalized to: $value"',
    ),
    (
        '_diag_line OK "Модуль ядра amneziawg загружен (AmneziaWG 3.0, $_d_mod_ver)"',
        '_diag_line OK "Kernel module amneziawg loaded (AmneziaWG 3.0, $_d_mod_ver)"',
    ),
    (
        '_diag_line OK "Модуль ядра amneziawg загружен ($_d_mod_ver)"',
        '_diag_line OK "Kernel module amneziawg loaded ($_d_mod_ver)"',
    ),
    (
        '_diag_line OK "Модуль ядра amneziawg загружен"',
        '_diag_line OK "Kernel module amneziawg loaded"',
    ),
    (
        'log "Перезапуск сервиса..."',
        'log "Restarting service..."',
    ),
    (
        'if ! confirm_action "перезапустить" "сервис"; then exit 1; fi',
        'if ! confirm_action "restart" "service"; then exit 1; fi',
    ),
    (
        'log "Сервис перезапущен."',
        'log "Service restarted."',
    ),
]


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    for name in ("awg_common.sh", "manage_amneziawg.sh"):
        path = root / name
        text = path.read_text(encoding="utf-8")
        for old, new in REPLACEMENTS:
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8")
        print(f"Updated {name}")


if __name__ == "__main__":
    main()
