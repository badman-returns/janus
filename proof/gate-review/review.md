The fleet got a front door: one screen that shows every machine at once, with the Cloud orb riding the build loop's own event stream and a pill that answers straight from the notification shade.

Read front.html and its orb first — everything else on this branch exists to feed that screen.

Behind it, mission control grew the fleet-wide routes it reads from, so a reply or a note you leave lands on the machine you meant rather than the one you last looked at.

The voice engine is the other half: seven states with barge-in, and Kokoro through a single tts.sh that falls back to say, so the machine can speak without talking over itself.

Last is build-loop.sh, which runs a plan unattended, waits out usage limits, and blocks on you instead of guessing — the reason the rest is safe to leave running overnight.
