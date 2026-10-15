#!/usr/bin/env python3
"""Composes the Play Store phone screenshots: a headline, a sub-line and the
raw emulator capture (store/captures, from tool/store/capture.sh) in a
device frame, 1080x1920 (9:16, inside Play's 2:1 rule), for every locale.

    tool/store/captions.py            all 11 locales
    tool/store/captions.py en-US de-DE

Output: fastlane/metadata/android/<locale>/images/phoneScreenshots/0N-*.png,
plus the two raw tablet captures copied unchanged to tenInchScreenshots.
Rendering: headless Chrome (like feature_graphic.sh) with the app's bundled
fonts, so Hebrew shapes and RTL lays out correctly. Pillow, when installed,
flattens the PNGs to 24-bit (Play wants no alpha channel); otherwise the
script says so and leaves Chrome's output.
"""
from __future__ import annotations

import html
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAPTURES = ROOT / 'store' / 'captures'
FASTLANE = ROOT / 'fastlane' / 'metadata' / 'android'
FONTS = ROOT / 'assets' / 'fonts'
CHROME = os.environ.get(
    'CHROME', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
)
if not os.access(CHROME, os.X_OK):
    CHROME = '/opt/google/chrome/chrome'

W, H = 1080, 1920
RTL = {'iw-IL'}

# The five shots, in Play order. The first four are what a search card shows.
# (name, source capture, form, theme)
SHOTS = [
    ('01-dashboard', 'phoneScreenshots/01-dashboard.png', 'phone', 'light'),
    ('02-wall-tablet', 'tenInchScreenshots/01-dashboard.png', 'tablet', 'dark'),
    ('03-no-cloud', 'phoneScreenshots/05-dashboard-dark.png', 'phone', 'dark'),
    ('04-controls', 'phoneScreenshots/02-device-controls.png', 'phone', 'light'),
    ('05-home-assistant', 'phoneScreenshots/03-devices.png', 'phone', 'light'),
]

# Headline and sub-line per locale, one pair per shot in SHOTS order.
# Headlines stay short enough for two lines at 84 px (about 36 characters).
STRINGS: dict[str, list[tuple[str, str]]] = {
    'en-US': [
        ('Your Zigbee devices, zero setup',
         'Needs Zigbee2MQTT and an MQTT broker. Scan once and every device gets a tile.'),
        ('Made for the wall tablet',
         'Kiosk mode: fullscreen, dimming, PIN lock. Dark by default.'),
        ('No cloud. No account. No ads.',
         'Free and open source. Your data stays on your broker.'),
        ('Every control, one tap away',
         'Brightness, white, colour, shutters and scenes.'),
        ('Works beside Home Assistant',
         'Same Zigbee2MQTT, same broker, faster control from your phone.'),
    ],
    'de-DE': [
        ('Zigbee-Geräte, null Einrichtung',
         'Braucht Zigbee2MQTT und einen MQTT-Broker. Einmal scannen, jedes Gerät bekommt eine Kachel.'),
        ('Gemacht fürs Wandtablet',
         'Kioskmodus: Vollbild, Dimmen, PIN-Sperre. Standardmäßig dunkel.'),
        ('Keine Cloud. Kein Konto. Keine Werbung.',
         'Kostenlos und Open Source. Deine Daten bleiben auf deinem Broker.'),
        ('Jede Steuerung, ein Tipp entfernt',
         'Helligkeit, Weißton, Farbe, Rollläden und Szenen.'),
        ('Läuft neben Home Assistant',
         'Gleiches Zigbee2MQTT, gleicher Broker, schnellere Steuerung vom Handy.'),
    ],
    'es-ES': [
        ('Tus dispositivos Zigbee, sin configurar',
         'Necesita Zigbee2MQTT y un bróker MQTT. Escanea una vez y cada dispositivo tiene su panel.'),
        ('Hecho para la tablet de pared',
         'Modo kiosco: pantalla completa, atenuación, bloqueo con PIN. Oscuro por defecto.'),
        ('Sin nube. Sin cuenta. Sin anuncios.',
         'Gratis y de código abierto. Tus datos se quedan en tu bróker.'),
        ('Todo el control a un toque',
         'Brillo, blanco, color, persianas y escenas.'),
        ('Funciona junto a Home Assistant',
         'Mismo Zigbee2MQTT, mismo bróker, control más rápido desde el móvil.'),
    ],
    'fr-FR': [
        ('Vos appareils Zigbee, zéro réglage',
         'Requiert Zigbee2MQTT et un broker MQTT. Un scan, une tuile par appareil.'),
        ('Conçu pour la tablette murale',
         'Mode kiosque : plein écran, atténuation, verrou PIN. Sombre par défaut.'),
        ('Sans cloud. Sans compte. Sans pub.',
         'Gratuit et open source. Vos données restent sur votre broker.'),
        ('Chaque réglage à portée de doigt',
         'Luminosité, blanc, couleur, volets et scènes.'),
        ('Fonctionne avec Home Assistant',
         'Même Zigbee2MQTT, même broker, contrôle plus rapide depuis le téléphone.'),
    ],
    'iw-IL': [
        ('מכשירי ה‑Zigbee שלכם, בלי הגדרות',
         'דורש Zigbee2MQTT ו‑broker MQTT. סריקה אחת, ואריח לכל מכשיר.'),
        ('נבנה לטאבלט הקיר',
         'מצב קיוסק: מסך מלא, עמעום, נעילת PIN. כהה כברירת מחדל.'),
        ('בלי ענן. בלי חשבון. בלי פרסומות.',
         'חינמי וקוד פתוח. הנתונים נשארים אצלכם, ב‑broker שלכם.'),
        ('כל שליטה במרחק הקשה',
         'בהירות, לבן, צבע, תריסים וסצנות.'),
        ('עובד לצד Home Assistant',
         'אותו Zigbee2MQTT, אותו broker, שליטה מהירה יותר מהטלפון.'),
    ],
    'nl-NL': [
        ('Je Zigbee-apparaten, nul instellen',
         'Vereist Zigbee2MQTT en een MQTT-broker. Eén scan, elk apparaat een tegel.'),
        ('Gemaakt voor het wandtablet',
         'Kioskmodus: volledig scherm, dimmen, pincode. Standaard donker.'),
        ('Geen cloud. Geen account. Geen reclame.',
         'Gratis en open source. Je gegevens blijven op je broker.'),
        ('Elke bediening, één tik verwijderd',
         'Helderheid, wit, kleur, rolluiken en scènes.'),
        ('Werkt naast Home Assistant',
         'Dezelfde Zigbee2MQTT, dezelfde broker, sneller bedienen vanaf je telefoon.'),
    ],
    'no-NO': [
        ('Zigbee-enhetene dine, null oppsett',
         'Krever Zigbee2MQTT og en MQTT-broker. Skann én gang, hver enhet får en flis.'),
        ('Laget for veggnettbrettet',
         'Kioskmodus: fullskjerm, dimming, PIN-lås. Mørk som standard.'),
        ('Ingen sky. Ingen konto. Ingen reklame.',
         'Gratis og åpen kildekode. Dataene dine blir på brokeren din.'),
        ('All styring ett trykk unna',
         'Lysstyrke, hvitt, farge, persienner og scener.'),
        ('Fungerer ved siden av Home Assistant',
         'Samme Zigbee2MQTT, samme broker, raskere styring fra mobilen.'),
    ],
    'pl-PL': [
        ('Urządzenia Zigbee bez konfiguracji',
         'Wymaga Zigbee2MQTT i brokera MQTT. Jeden skan, kafelek dla każdego urządzenia.'),
        ('Stworzony na tablet ścienny',
         'Tryb kiosku: pełny ekran, przyciemnianie, blokada PIN. Domyślnie ciemny.'),
        ('Bez chmury. Bez konta. Bez reklam.',
         'Darmowy i open source. Twoje dane zostają na twoim brokerze.'),
        ('Każde sterowanie na jedno dotknięcie',
         'Jasność, biel, kolor, rolety i sceny.'),
        ('Działa obok Home Assistant',
         'Ten sam Zigbee2MQTT, ten sam broker, szybsze sterowanie z telefonu.'),
    ],
    'pt-BR': [
        ('Dispositivos Zigbee sem configuração',
         'Requer Zigbee2MQTT e um broker MQTT. Um scan, um painel para cada dispositivo.'),
        ('Feito para o tablet de parede',
         'Modo quiosque: tela cheia, escurecimento, bloqueio por PIN. Escuro por padrão.'),
        ('Sem nuvem. Sem conta. Sem anúncios.',
         'Grátis e de código aberto. Seus dados ficam no seu broker.'),
        ('Todo controle a um toque',
         'Brilho, branco, cor, persianas e cenas.'),
        ('Funciona ao lado do Home Assistant',
         'Mesmo Zigbee2MQTT, mesmo broker, controle mais rápido pelo celular.'),
    ],
    'ru-RU': [
        ('Zigbee-устройства без настройки',
         'Нужен Zigbee2MQTT и MQTT-брокер. Одно сканирование — и всё на плитках.'),
        ('Создан для настенного планшета',
         'Режим киоска: полный экран, затемнение, PIN-блокировка. Тёмный по умолчанию.'),
        ('Без облака, аккаунта и рекламы.',
         'Бесплатно и с открытым кодом. Данные остаются на вашем брокере.'),
        ('Любое управление в одно касание',
         'Яркость, белый, цвет, шторы и сцены.'),
        ('Работает рядом с Home Assistant',
         'Тот же Zigbee2MQTT, тот же брокер, быстрее управлять с телефона.'),
    ],
    'sv-SE': [
        ('Dina Zigbee-enheter, noll inställning',
         'Kräver Zigbee2MQTT och en MQTT-broker. Skanna en gång, varje enhet får en bricka.'),
        ('Gjord för väggplattan',
         'Kioskläge: helskärm, dimning, PIN-lås. Mörk som standard.'),
        ('Inget moln. Inget konto. Inga annonser.',
         'Gratis och öppen källkod. Dina data stannar på din broker.'),
        ('All styrning ett tryck bort',
         'Ljusstyrka, vitt, färg, rullgardiner och scener.'),
        ('Fungerar bredvid Home Assistant',
         'Samma Zigbee2MQTT, samma broker, snabbare styrning från mobilen.'),
    ],
}

# Signal palette (docs/design/signal-2.0.md): ivory, ink, amber.
THEME = {
    'light': dict(bg='#F6F3EC', fg='#1C1A16', sub='#5B5446', frame='#1C1A16', accent='#F0A544'),
    'dark': dict(bg='#15130F', fg='#EFE9DD', sub='#B8B0A2', frame='#2E2A24', accent='#F0A544'),
}

CSS = """
@font-face{font-family:SG;src:url('file://%(fonts)s/SpaceGrotesk-Bold.ttf');font-weight:700}
@font-face{font-family:Plex;src:url('file://%(fonts)s/IBMPlexSans-Regular.ttf');font-weight:400}
@font-face{font-family:Plex;src:url('file://%(fonts)s/IBMPlexSans-SemiBold.ttf');font-weight:600}
@font-face{font-family:PlexHe;src:url('file://%(fonts)s/IBMPlexSansHebrew-Regular.ttf');font-weight:400}
@font-face{font-family:PlexHe;src:url('file://%(fonts)s/IBMPlexSansHebrew-SemiBold.ttf');font-weight:600}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:%(w)dpx;height:%(h)dpx;overflow:hidden}
body{background:%(bg)s;color:%(fg)s;position:relative;
  font-family:Plex,PlexHe,sans-serif;-webkit-font-smoothing:antialiased}
.text{position:absolute;left:72px;right:72px;top:112px}
h1{font-family:SG,PlexHe,sans-serif;font-weight:700;font-size:84px;line-height:1.08;
  letter-spacing:-1.5px;color:%(fg)s}
[dir=rtl] h1{font-family:PlexHe,SG,sans-serif;font-weight:600;letter-spacing:0}
p{margin-top:26px;font-size:40px;line-height:1.3;color:%(sub)s;max-width:900px}
.bar{position:absolute;left:72px;top:64px;width:120px;height:12px;border-radius:6px;background:%(accent)s}
[dir=rtl] .bar{left:auto;right:72px}
.phone{position:absolute;left:%(px)dpx;top:%(py)dpx;width:%(pw)dpx;height:%(ph)dpx;
  border:14px solid %(frame)s;border-radius:64px;overflow:hidden;background:%(frame)s}
.phone img{display:block;width:100%%;height:100%%;border-radius:50px}
.tablet{position:absolute;left:%(tx)dpx;top:%(ty)dpx;width:%(tw)dpx;height:%(th)dpx;
  border:18px solid %(frame)s;border-radius:44px;overflow:hidden;background:%(frame)s}
.tablet img{display:block;width:100%%;height:100%%;border-radius:26px}
[dir=rtl] .tablet{left:auto;right:%(tx)dpx}
"""

# Phone: 620 wide including the frame, 1080x2400 capture inside.
PW = 620
PH = round((PW - 28) * 2400 / 1080) + 28
PX, PY = (W - PW) // 2, H - PH - 24
# Tablet: wider than the canvas so the dashboard reads at card size; the
# bleed on the left also crops the navigation rail, which kiosk mode hides.
TW = 1500
TH = round((TW - 36) * 1600 / 2560) + 36
TX, TY = -120, 560 + (H - 560 - TH) // 2


def page(locale: str, headline: str, sub: str, src: Path, form: str, theme: str) -> str:
    t = THEME[theme]
    css = CSS % dict(
        fonts=FONTS, w=W, h=H, px=PX, py=PY, pw=PW, ph=PH, tx=TX, ty=TY, tw=TW, th=TH, **t
    )
    d = 'rtl' if locale in RTL else 'ltr'
    lang = locale.split('-')[0].replace('iw', 'he')
    frame = (
        f'<div class="phone"><img src="file://{src}"></div>'
        if form == 'phone'
        else f'<div class="tablet"><img src="file://{src}"></div>'
    )
    return (
        f'<!doctype html><html lang="{lang}" dir="{d}"><head><meta charset="utf-8">'
        f'<style>{css}</style></head><body dir="{d}">'
        f'<div class="bar"></div>'
        f'<div class="text"><h1>{html.escape(headline)}</h1><p>{html.escape(sub)}</p></div>'
        f'{frame}</body></html>'
    )


def render(html_path: Path, out: Path, profile: Path) -> None:
    out.unlink(missing_ok=True)
    proc = subprocess.Popen(
        [
            CHROME, '--headless=new', '--disable-gpu', '--no-sandbox',
            f'--user-data-dir={profile}', '--hide-scrollbars',
            '--allow-file-access-from-files', '--force-device-scale-factor=1',
            f'--window-size={W},{H}', f'--screenshot={out}', f'file://{html_path}',
        ],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    # Headless Chrome on macOS can hang after writing the file: wait for it,
    # then stop the process (feature_graphic.sh does the same).
    for _ in range(120):
        if out.exists() and out.stat().st_size > 0:
            break
        time.sleep(0.5)
    time.sleep(0.5)
    proc.kill()
    proc.wait()
    if not (out.exists() and out.stat().st_size > 0):
        sys.exit(f'render failed: {out}')


def flatten(out: Path) -> bool:
    """Drop the alpha channel (Play wants 24-bit PNG). True when done."""
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        return False
    with Image.open(out) as im:
        if im.mode == 'RGB':
            return True
        rgb = Image.new('RGB', im.size)
        rgb.paste(im.convert('RGBA'), mask=None)
        rgb.save(out, optimize=True)
    return True


def main(argv: list[str]) -> None:
    locales = argv or sorted(STRINGS)
    for loc in locales:
        if loc not in STRINGS:
            sys.exit(f'no strings for {loc}')
        if not (CAPTURES / loc).is_dir():
            sys.exit(f'no captures for {loc} (run tool/store/capture.sh)')
    flattened = True
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        for loc in locales:
            out_dir = FASTLANE / loc / 'images' / 'phoneScreenshots'
            if out_dir.exists():
                shutil.rmtree(out_dir)
            out_dir.mkdir(parents=True)
            for (name, src, form, theme), (headline, sub) in zip(SHOTS, STRINGS[loc]):
                src_path = CAPTURES / loc / src
                if not src_path.exists():
                    sys.exit(f'missing capture {src_path}')
                html_path = tmpdir / f'{loc}-{name}.html'
                html_path.write_text(page(loc, headline, sub, src_path, form, theme), 'utf-8')
                out = out_dir / f'{name}.png'
                render(html_path, out, tmpdir / f'profile-{loc}')
                flattened = flatten(out) and flattened
                print(out.relative_to(ROOT))
            tab_dir = FASTLANE / loc / 'images' / 'tenInchScreenshots'
            if tab_dir.exists():
                shutil.rmtree(tab_dir)
            shutil.copytree(CAPTURES / loc / 'tenInchScreenshots', tab_dir)
    if not flattened:
        print('note: Pillow not installed, PNGs keep the alpha channel '
              '(pip install pillow, then rerun)', file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1:])
