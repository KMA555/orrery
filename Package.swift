// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Orrery",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Orrery", targets: ["Orrery"])],
    targets: [
        .executableTarget(
            name: "Orrery",
            linkerSettings: [
                // マイクと音声認識の用途説明をバイナリに埋め込む（許可ダイアログに必要）
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "AppResources/Info.plist"
                ])
            ]
        )
    ]
)
