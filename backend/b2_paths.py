"""Independent expected routes for the existing scenario; generate the B2 path table."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def cases():
    result = []
    for condition in ('free', 'occupied'):
        space = 'space_' + condition
        placement = 'regular' if condition == 'free' else 'alternative'
        for recovery in (False, True):
            prefix = [('opening', 'demand_removal', 'conflict'), ('conflict', 'recover_help', space)] if recovery else [('opening', 'offer_help', space)]
            placed = [('space_free', 'place_free', 'verify')] if condition == 'free' else [('space_occupied', 'check_alternative', 'alternative'), ('alternative', 'place_alternative', 'verify')]
            stem = condition + ('-recovery' if recovery else '-help')
            for last, terminal, outcome, loyalty in [('confirm_clear', 'resolved', 'resolved', 58), ('finish_unchecked', 'unchecked', 'not_verified', 50)]:
                result.append(dict(id=stem + '-' + outcome, condition=condition, edges=prefix + placed + [('verify', last, terminal)], outcome=outcome, loyalty=loyalty, safety=100, placement=placement, clear=outcome == 'resolved'))
            allow_edges = [('space_free', 'allow_luggage', 'allowed')] if condition == 'free' else [('space_occupied', 'check_alternative', 'alternative'), ('alternative', 'allow_luggage', 'allowed')]
            result.append(dict(id=stem + '-allow', condition=condition, edges=prefix + allow_edges, outcome='allowed_blocked', loyalty=54, safety=80, placement=None, clear=False))
            if condition == 'occupied':
                result.append(dict(id=stem + '-repeat', condition=condition, edges=prefix + [('space_occupied', 'repeat_request', 'unresolved')], outcome='unresolved', loyalty=40, safety=100, placement=None, clear=False))
        for last, terminal, outcome, loyalty, safety in [('repeat_demand', 'unresolved', 'unresolved', 40, 100), ('allow_luggage', 'allowed', 'allowed_blocked', 54, 80)]:
            result.append(dict(id=condition + '-demand-' + last, condition=condition, edges=[('opening', 'demand_removal', 'conflict'), ('conflict', last, terminal)], outcome=outcome, loyalty=loyalty, safety=safety, placement=None, clear=False))
        result.append(dict(id=condition + '-allow', condition=condition, edges=[('opening', 'allow_luggage', 'allowed')], outcome='allowed_blocked', loyalty=54, safety=80, placement=None, clear=False))
    return result


def render():
    config = json.loads((ROOT / 'backend/data/luggage-v1.json').read_text(encoding='utf-8'))
    lines = ['# Б2: таблица путей «Чемодан в проходе»', '',
             'Источник: `backend/data/luggage-v1.json`, `1.0.0-draft`. Ожидаемые пути закреплены отдельно в `backend/b2_paths.py`; HTTP-тесты сверяют их с сервером и проверяют полноту относительно конфига. Обновление таблицы: `python3 backend/b2_paths.py`; проверка: `python3 backend/b2_paths.py --check`.', '',
             'Начало: `opening`, версия 1, лояльность 50, безопасность 100, проход не подтверждён свободным, размещения нет. Условие багажа неизменно. Каждый принятый выбор увеличивает версию на 1 и добавляет одну запись журнала. Служебный узел `space` сам выбирает ветку; отдельного действия/баллов за него нет.', '',
             '## Все переходы', '', '| Условие | Узел → действие | Следующий узел | Изменение состояния | Объяснение в журнале | Итог |', '|---|---|---|---|---|---|']
    for condition in ('free', 'occupied'):
        edges = sorted({tuple(e) for c in cases() if c['condition'] == condition for e in c['edges']})
        for before, aid, after in edges:
            action = next(a for a in config['nodes'][before]['actions'] if a['id'] == aid)
            effects = json.dumps(action['effects'], ensure_ascii=False) if action['effects'] else 'Шкалы и факты без изменения'
            outcome = config['nodes'][after].get('outcome', 'Продолжение')
            lines.append(f"| {condition} | `{before}` → `{aid}` | `{after}` | {effects} | {action['explanation']} | {outcome} |")
    lines += ['| occupied | `space_occupied` → `place_free` | Переход запрещён | Без изменений, HTTP 422 `action_unavailable` | Условие размещения не выполнено. В журнал не добавляется. | Попытка продолжается |', '',
              '## Все 20 завершённых путей', '', '| ID / начальное условие | Действия по порядку | Итог | Лояльность / безопасность | Факты | Версия |', '|---|---|---|---|---|---|']
    for c in cases():
        actions = ' → '.join('`' + edge[1] + '`' for edge in c['edges'])
        facts = f"placement={c['placement']}; aisle_clear={str(c['clear']).lower()}"
        if any(e[1] == 'check_alternative' for e in c['edges']):
            facts += '; alternative_checked=true'
        if c['outcome'] == 'allowed_blocked':
            facts += '; critical_marks=[aisle_left_blocked]'
        lines.append(f"| {c['id']} | {actions} | {c['outcome']} | {c['loyalty']} / {c['safety']} | {facts} | {1 + len(c['edges'])} |")
    lines += ['', 'Итоговая общая лояльность равна лояльности владельца; до завершения она null. `completed` означает наличие разбора, а не обязательное устранение проблемы. Безопасность 100 при unresolved/not_verified не подтверждает свободный проход. Профильные очки и достижения в Б1/Б2 ещё отсутствуют: однократность проверяется для дельт шкал, критических отметок и записей журнала.', '',
              'Все тексты и числа остаются демонстрационными; исходный датасет не предоставлен. Новые сценарии не добавлены.', '']
    return '\n'.join(lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = ROOT / 'docs/content/b2-paths.md'
    if args.check:
        if target.read_text(encoding='utf-8') != render():
            raise SystemExit('FAIL: path table differs; run python3 backend/b2_paths.py')
        print('PASS: path table matches 20 expected routes and current content')
    else:
        target.write_text(render(), encoding='utf-8')
        print(target)
