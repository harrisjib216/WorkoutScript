/// Scripts to start from, the same ones as in the package's Examples folder.
struct Sample: Identifiable {
    var name: String
    var text: String
    var id: String { name }

    static let all = [
        Sample(name: "Track 800s", text: """
            # Six 800s on the track, a lap easy between each.
            running outdoor "Track 800s"

            warmup 15min @ zone 2

            6x {
              800m @ 3:50-4:00/km "800"
              recover 400m
            }

            cooldown 10min

            """),
        Sample(name: "Sweet spot 3x12", text: """
            # Three 12-minute efforts just under threshold, for a trainer.
            cycling indoor "Sweet spot 3x12"

            warmup 10min @ 150-180W

            3x {
              12min @ 250-265W
              recover 5min @ 150W
            }

            cooldown 10min

            """),
        Sample(name: "Hill repeats", text: """
            running outdoor "Hill repeats"

            warmup 15min
            8x {
              90s @ zone 4 "Up"
              recover 2min "Jog down"
            }
            cooldown 15min

            """),
        Sample(name: "Long run, fast finish", text: """
            # Easy for most of it, then pick it up.
            running outdoor "Long run, fast finish"

            warmup 2km
            60min @ zone 2
            20min @ avg 4:30/km
            cooldown

            """),
        Sample(name: "Pool 100s", text: """
            # Send-offs on the clock: each 100 has to fit inside 1:45.
            swimming indoor "Pool 100s"

            warmup 200m
            8x 100m in 1:45 "On the clock"
            cooldown 200m

            """),
        Sample(name: "Easy + strides", text: """
            # Strides after an easy run: the watch counts them, you decide when each one ends.
            running outdoor "Easy + strides"

            30min @ 140-150bpm
            6x {
              20s @ 180-190spm "Stride"
              recover open
            }

            """),
    ]
}
