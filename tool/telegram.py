#!/usr/bin/env python3
"""The ZigDash Telegram group (docs/design/support.md, Community) through
@zigdash_bot. Token in tool/.telegram_bot (gitignored).

  tool/telegram.py read            new messages since the last read
  tool/telegram.py post <topic> -  post stdin to a topic (announcements, help, ideas, general)

Posting is done only after the group's owner has approved the text.
"""
import json, os, sys, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN = open(os.path.join(HERE, '.telegram_bot')).read().strip()
CHAT = '@zigdash_app'
TOPICS = {'general': None, 'announcements': 2, 'help': 3, 'ideas': 4}
STATE = os.path.join(HERE, '.telegram_offset')


def api(method, **params):
    data = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None}).encode()
    with urllib.request.urlopen(f'https://api.telegram.org/bot{TOKEN}/{method}', data, timeout=30) as r:
        out = json.load(r)
    if not out.get('ok'):
        sys.exit(f'{method}: {out}')
    return out['result']


def read():
    offset = int(open(STATE).read()) if os.path.exists(STATE) else None
    updates = api('getUpdates', offset=offset, timeout=0, allowed_updates=json.dumps(['message']))
    names = {v: k for k, v in TOPICS.items()}
    for u in updates:
        m = u.get('message') or {}
        who = (m.get('from') or {}).get('first_name', '?')
        topic = names.get(m.get('message_thread_id'), 'general')
        text = m.get('text') or m.get('caption') or '[' + ', '.join(k for k in m if k.endswith('_members') or k in ('photo', 'document', 'sticker')) + ']'
        print(f'#{m.get("message_id")} [{topic}] {who}: {text}')
    if updates:
        open(STATE, 'w').write(str(updates[-1]['update_id'] + 1))
    else:
        print('(nothing new)')


def post(topic):
    text = sys.stdin.read().strip()
    if not text:
        sys.exit('nothing to post')
    r = api('sendMessage', chat_id=CHAT, message_thread_id=TOPICS[topic], text=text,
            disable_web_page_preview='true')
    print(f'posted #{r["message_id"]} to {topic}')


if __name__ == '__main__':
    cmd = sys.argv[1:2]
    if cmd == ['read']:
        read()
    elif cmd == ['post'] and len(sys.argv) == 3 and sys.argv[2] in TOPICS:
        post(sys.argv[2])
    else:
        sys.exit(__doc__)
