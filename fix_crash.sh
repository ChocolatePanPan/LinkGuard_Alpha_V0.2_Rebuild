sed -i '' 's/let payload = box.data.subdata(in: Self.headerSize..<totalLen)/let startIndex = box.data.startIndex\
            let payload = box.data.subdata(in: (startIndex + Self.headerSize)..<(startIndex + totalLen))/' linkguardMB/LinkGuardHQ/LinkGuardHQ/AudioStreamServer.swift
