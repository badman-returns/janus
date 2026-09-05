#!/usr/bin/env python3
"""The voice loop's state machine, with no audio and no I/O in it. Events go in; a state and a list
of actions come out; loop.py performs the actions. --selftest is the contract the loop relies on."""
import time
STATES = ('idle', 'listening', 'thinking', 'speaking', 'waiting', 'muted', 'offline')

class Machine:
    def __init__(self, now=time.monotonic):
        self.now = now; self.state = 'idle'; self.since = now()
        self.flags = {'dnd': False, 'meeting': False, 'voice_on': False}
        self.current = None        # [reply, sentences, index] being spoken
        self.paused = None         # the reply to resume after an interruption is answered
        self.queue = []            # replies that landed mid-utterance, each spoken in its turn
        self.pending_note = None   # stem of the note whose reply we wait for
        self.about = None          # the card a waiting state is about
        self.solicited = False     # the turn began with the operator speaking or pressing the key
        self.empty_turns = 0       # listening opened and closed with nothing said (false triggers)

    def _go(self, s, out, **kw):
        if s != self.state:
            out.append(('state', s, dict(kw, since=self.now()))); self.state = s; self.since = self.now()
    def muted(self): return self.flags['dnd'] or self.flags['meeting']
    def _rest(self): return 'muted' if self.muted() else 'idle'

    def feed(self, ev, **a):
        out = []
        if ev == 'flag':
            self.flags[a['name']] = a['value']
            if self.muted() and self.state in ('idle', 'waiting'): self._go('muted', out)
            if not self.muted() and self.state == 'muted': self._go('idle', out)
        elif ev == 'offline': self._go('offline', out)
        elif ev == 'online': self._go('idle', out)
        elif ev in ('wake', 'key'):
            if self.state == 'offline': return out
            if ev == 'wake' and self.muted(): return out                  # the name is off under dnd / meeting
            if self.state == 'speaking':
                out.append(('pause_playback',)); self.paused = self.current; self.current = None
            self.solicited = True; out.append(('open_mic',)); self._go('listening', out, door=ev)
        elif ev == 'speech_end':
            if self.state != 'listening': return out
            text = (a.get('text') or '').strip(); out.append(('close_mic',))
            if not text:
                self.empty_turns += 1
                if self.paused:
                    self.current = self.paused; self.paused = None
                    out.append(('resume_playback', self.current[0], self.current[2])); self._go('speaking', out)
                else: self._go(self._rest(), out)
                return out
            stem = a.get('stem') or f"note-{int(self.now()*1000)}-voice"
            self.pending_note = stem
            out.append(('write_note', stem, text, self.paused[0] if self.paused else None, self.paused[2] if self.paused else None))
            self._go('thinking', out, note=stem)
        elif ev == 'typed':
            stem = a.get('stem') or f"note-{int(self.now()*1000)}-typed"
            self.pending_note = stem; self.solicited = bool(a.get('voice'))
            out.append(('write_note', stem, a['text'], None, None)); self._go('thinking', out, note=stem)
        elif ev == 'reply':
            rid, sents, speak = a['stem'], a['sentences'], a.get('speak')
            matches = (rid == self.pending_note)
            # spoken when he spoke or pressed the key, on speak: yes, and otherwise only with voice.on
            will_speak = speak == 'yes' or (matches and self.solicited) or (speak is None and self.flags['voice_on'])
            if speak == 'no': will_speak = False
            if self.muted() and not (matches and self.solicited): will_speak = False
            if matches: self.pending_note = None
            if self.state == 'listening':                                     # never speak into an open microphone
                out.append(('show_reply', rid, sents, a.get('via'), False)); return out
            out.append(('show_reply', rid, sents, a.get('via'), will_speak))
            if will_speak and sents:
                if self.state == 'speaking':                                  # nothing overlaps: it waits its turn
                    self.queue.append((rid, sents, a.get('needs')))
                else:
                    self.current = [rid, sents, 0]; self.about = a.get('needs')
                    out.append(('speak', rid, 0)); self._go('speaking', out, reply=rid)
            elif matches:
                q = a.get('needs') or (sents and sents[-1].endswith('?'))
                self._go('waiting' if q else self._rest(), out, about=a.get('needs'))
        elif ev == 'sentence_done':
            if self.state != 'speaking' or not self.current: return out
            self.current[2] += 1
            if self.current[2] < len(self.current[1]): out.append(('speak', self.current[0], self.current[2]))
            else:
                done = self.current; self.current = None
                if self.paused:
                    self.current = self.paused; self.paused = None
                    out.append(('say_bridge', 'Back to where I was.')); out.append(('speak', self.current[0], self.current[2]))
                elif self.queue:
                    rid, sents, needs = self.queue.pop(0)                     # the next one waiting; still speaking
                    self.current = [rid, sents, 0]; self.about = needs; out.append(('speak', rid, 0))
                else:
                    needs = self.about; self.about = None
                    q = needs or done[1][-1].endswith('?')
                    self._go('waiting' if q else self._rest(), out, about=needs)
        elif ev == 'stop':
            if self.state == 'speaking': out.append(('pause_playback',))
            self.current = None; self.paused = None; self.pending_note = None; self.queue = []; out.append(('close_mic',))
            self._go(self._rest(), out)
        elif ev == 'timeout':
            if self.state == 'waiting': self._go(self._rest(), out)
            elif self.state == 'thinking': out.append(('say_bridge', 'Still working. I will tell you.')); self.pending_note = None; self._go(self._rest(), out)
            elif self.state == 'listening': return self.feed('speech_end', text='')
        return out

def selftest():
    t = [0.0]; m = Machine(now=lambda: t[0])
    def kinds(out): return [o[0] + ('>' + o[1] if o[0] == 'state' else '') for o in out]
    assert kinds(m.feed('wake')) == ['open_mic', 'state>listening']
    o = m.feed('speech_end', text="what's waiting", stem='n1'); assert ('write_note', 'n1', "what's waiting", None, None) in o and m.state == 'thinking'
    o = m.feed('reply', stem='n1', sentences=['Two things.', 'The video is ready.', 'Want it?']); assert m.state == 'speaking' and ('speak', 'n1', 0) in o
    m.feed('sentence_done')                                                  # sentence 1 is playing
    o = m.feed('wake'); assert ('pause_playback',) in o and m.state == 'listening' and m.paused[2] == 1
    o = m.feed('speech_end', text='why two?', stem='n2'); assert o[-1][1] == 'thinking' and [x for x in o if x[0] == 'write_note'][0][3:] == ('n1', 1)
    m.feed('reply', stem='n2', sentences=['Because of the walk-in.'])
    o = m.feed('sentence_done'); assert ('say_bridge', 'Back to where I was.') in o and ('speak', 'n1', 1) in o and m.state == 'speaking'
    m.feed('sentence_done'); m.feed('sentence_done'); assert m.state == 'waiting', m.state   # it ended with a question
    m.feed('flag', name='dnd', value=True); assert m.state == 'muted'
    assert m.feed('wake') == []                                               # the name is off
    m.feed('key'); assert m.state == 'listening'                              # the key still works
    m.feed('speech_end', text='status', stem='n3'); m.feed('reply', stem='n3', sentences=['All quiet.']); assert m.state == 'speaking'
    m.feed('sentence_done'); assert m.state == 'muted'
    m.feed('flag', name='dnd', value=False); assert m.state == 'idle'
    m.feed('reply', stem='brief', sentences=['Good morning.'], speak='yes'); assert m.state == 'speaking'   # scheduled, allowed
    m.feed('stop'); assert m.state == 'idle'
    o = m.feed('reply', stem='other', sentences=['Unsolicited.']); assert m.state == 'idle' and o[0][4] is False   # shown, not spoken
    m.feed('flag', name='voice_on', value=True); m.feed('reply', stem='other2', sentences=['Now spoken.']); assert m.state == 'speaking'
    m.feed('stop'); m.feed('typed', text='status', stem='t1'); assert m.state == 'thinking'
    o = m.feed('reply', stem='t1', sentences=['Quiet.']); assert m.state == 'speaking'      # voice.on is set, so it speaks
    m.feed('stop'); m.feed('flag', name='voice_on', value=False); m.feed('typed', text='status', stem='t2')
    o = m.feed('reply', stem='t2', sentences=['Quiet.']); assert m.state == 'idle' and o[0][4] is False   # typed, answered in writing
    m.feed('key'); m.feed('speech_end', text='status', stem='q1'); m.feed('wake'); assert m.state == 'listening'
    o = m.feed('reply', stem='q1', sentences=['Here.'])                       # it landed with the mic open
    assert m.state == 'listening' and not [x for x in o if x[0] == 'speak'] and o[0][4] is False
    m.feed('speech_end', text='and the other one', stem='q2'); assert m.state == 'thinking'
    m.feed('reply', stem='q2', sentences=['One.', 'Two.']); assert m.state == 'speaking'
    o = m.feed('reply', stem='q3', sentences=['Queued.'], speak='yes')        # it waits its turn, it does not overlap
    assert m.state == 'speaking' and not [x for x in o if x[0] == 'speak'] and o[0][4] is True
    m.feed('sentence_done')                                                   # 'Two.' is playing
    o = m.feed('sentence_done'); assert ('speak', 'q3', 0) in o and m.state == 'speaking'   # the queue drains
    m.feed('sentence_done'); assert m.state == 'idle'
    print('PASS state selftest')

if __name__ == '__main__':
    import sys
    if '--selftest' in sys.argv: selftest()
