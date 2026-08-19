#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: render-icon.swift <output.png>\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let inset: CGFloat = 64
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)

NSColor(calibratedRed: 0.102, green: 0.118, blue: 0.145, alpha: 1).setFill()
path.fill()

NSGraphicsContext.current?.cgContext.saveGState()
path.addClip()
let glow = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.824, green: 0.600, blue: 0.133, alpha: 0.22),
        NSColor.clear,
    ]
)
glow?.draw(
    from: NSPoint(x: size * 0.5, y: size * 0.78),
    to: NSPoint(x: size * 0.5, y: size * 0.28),
    options: []
)
NSGraphicsContext.current?.cgContext.restoreGState()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 548, y: 742))
bolt.line(to: NSPoint(x: 368, y: 518))
bolt.line(to: NSPoint(x: 496, y: 518))
bolt.line(to: NSPoint(x: 456, y: 282))
bolt.line(to: NSPoint(x: 656, y: 526))
bolt.line(to: NSPoint(x: 528, y: 526))
bolt.close()
NSColor(calibratedRed: 0.918, green: 0.722, blue: 0.227, alpha: 1).setFill()
bolt.fill()

let track = NSRect(x: 272, y: 214, width: 480, height: 36)
let trackPath = NSBezierPath(roundedRect: track, xRadius: 18, yRadius: 18)
NSColor(calibratedRed: 0.180, green: 0.204, blue: 0.239, alpha: 1).setFill()
trackPath.fill()

let fill = NSRect(x: 272, y: 214, width: 286, height: 36)
let fillPath = NSBezierPath(roundedRect: fill, xRadius: 18, yRadius: 18)
NSColor(calibratedRed: 0.247, green: 0.725, blue: 0.314, alpha: 1).setFill()
fillPath.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

try png.write(to: output)
