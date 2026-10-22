"""Wait for the opponent-side engine request, without inspecting player inputs."""
import json, time, sys
from pathlib import Path
path = Path('build/codex-duel/state.json')
last = sys.argv[1] if len(sys.argv) > 1 else ''
end = time.monotonic() + 45
while time.monotonic() < end:
    try:
        state = json.loads(path.read_text())
        frame = state.get('frame', {})
        if state.get('outcome') or (not state.get('submitted') and frame.get('decisionID') != last and frame.get('slots') and not frame.get('waiting') and not frame.get('ended')):
            print(json.dumps({'phase':state['phase'],'submitted':state['submitted'],'outcome':state['outcome'],'error':state['error'],
                'turn':frame.get('turn'),'decisionID':frame.get('decisionID'),'own':frame.get('own'),
                'foe':frame.get('foe'),'slots':frame.get('slots'),'field':frame.get('field'),'log':frame.get('log',[])[-18:]},ensure_ascii=False))
            break
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    time.sleep(0.15)
else:
    print('WAITING_FOR_PLAYER')
