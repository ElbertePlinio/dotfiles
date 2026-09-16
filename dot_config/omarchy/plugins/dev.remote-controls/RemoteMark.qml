import QtQuick
import qs.Commons

Canvas {
    id: root
    property color ink: Color.foreground
    property color accent: Color.accent
    onInkChanged: requestPaint()
    onAccentChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.scale(width / 24, height / 24)
        ctx.strokeStyle = root.ink
        ctx.lineWidth = 1.7
        ctx.lineCap = "square"
        ctx.beginPath()
        ctx.moveTo(4, 9); ctx.lineTo(4, 4); ctx.lineTo(9, 4)
        ctx.moveTo(4, 15); ctx.lineTo(4, 20); ctx.lineTo(9, 20)
        ctx.moveTo(15, 20); ctx.lineTo(20, 20); ctx.lineTo(20, 15)
        ctx.stroke()
        ctx.fillStyle = root.accent
        ctx.beginPath()
        ctx.arc(18, 6, 2.3, 0, Math.PI * 2)
        ctx.fill()
    }
}
