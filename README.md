# Alarm sound masters — 2026-09-24

Source WAVs made by the PM for the alarm-sound catalogue. Stored here unchanged,
as delivered; this branch has no history in common with `main` and is not meant
to be merged. The app ships 16-bit `.caf` conversions of these files under
`SnoozePay/SnoozePay/Resources/Sounds/`, not the WAVs themselves.

| file | channels | bit depth | rate | duration |
|---|---|---|---|---|
| birds.wav | 2 | 16 | 44.1 kHz | 2.22 s |
| hawk.wav | 2 | 24 | 44.1 kHz | 2.67 s |
| morning.wav | 2 | 24 | 44.1 kHz | 4.11 s |
| sirena.wav | 2 | 16 | 44.1 kHz | 17.99 s |
| spaceship.wav | 2 | 16 | 44.1 kHz | 25.76 s |

Pull them into a working tree:

    git fetch origin assets/alarm-sounds-2026-09-24
    git show origin/assets/alarm-sounds-2026-09-24:hawk.wav > /tmp/hawk.wav
