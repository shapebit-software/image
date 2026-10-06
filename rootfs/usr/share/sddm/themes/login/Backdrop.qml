// The backdrop: dusk behind soft ridges. It is drawn, not a picture, so it
// fits every screen size.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Rectangle {
    id: backdrop

    clip: true
    gradient: Gradient {
        GradientStop { position: 0.00; color: "#1f1a3c" }
        GradientStop { position: 0.34; color: "#342351" }
        GradientStop { position: 0.44; color: "#4c2943" }
        GradientStop { position: 0.535; color: "#653035" }
        GradientStop { position: 0.63; color: "#7c3829" }
        GradientStop { position: 0.72; color: "#85482d" }
    }

    // A soft light, placed by its center and radii as fractions of the screen.
    component Glow: Shape {
        id: glow

        property real centerX
        property real centerY
        property real radiusX
        property real radiusY
        property color tint

        x: (centerX - radiusX) * backdrop.width
        y: (centerY - radiusY) * backdrop.height
        width: 200
        height: 200
        transform: Scale {
            xScale: glow.radiusX * backdrop.width / 100
            yScale: glow.radiusY * backdrop.height / 100
        }

        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 100
                centerY: 100
                centerRadius: 100
                focalX: 100
                focalY: 100
                GradientStop { position: 0.0; color: glow.tint }
                GradientStop { position: 0.5; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, glow.tint.a * 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, 0) }
            }
            PathAngleArc { centerX: 100; centerY: 100; radiusX: 100; radiusY: 100; sweepAngle: 360 }
        }
    }

    // Haze at the top, and the sun low in the sky.
    Glow { centerX: 0.17; centerY: 0.02; radiusX: 0.55; radiusY: 0.4; tint: Qt.rgba(0.66, 0.6, 0.86, 0.13) }
    Glow { centerX: 0.88; centerY: 0.06; radiusX: 0.4; radiusY: 0.3; tint: Qt.rgba(0.75, 0.62, 0.8, 0.09) }
    Glow { centerX: 0.63; centerY: 0.67; radiusX: 0.42; radiusY: 0.22; tint: Qt.rgba(0.82, 0.62, 0.3, 0.75) }

    // The ridges are drawn small and blurred there, then stretched over the
    // screen, so the blur costs the same on every screen. The drawing reaches
    // a tenth past each edge of the screen, because the blur fades at its own
    // edges. Paths use a 1000 by 1000 grid for the screen.
    Item {
        id: ridges
        width: 600
        height: 600
        visible: false

        Shape {
            x: 50
            y: 50
            scale: 0.5
            transformOrigin: Item.TopLeft

            ShapePath {
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    y1: 660
                    y2: 1000
                    GradientStop { position: 0.0; color: "#5e4144" }
                    GradientStop { position: 0.45; color: "#503a43" }
                    GradientStop { position: 0.65; color: "#463444" }
                    GradientStop { position: 0.85; color: "#342a40" }
                }
                PathSvg {
                    path: "M-100 725 C0 715 80 745 120 730 C160 715 190 665 235 667 C285 670 300 715 360 730 "
                        + "C420 745 450 735 510 755 C570 775 610 785 660 760 C710 735 730 745 790 760 "
                        + "C850 775 910 720 1100 715 V1100 H-100 Z"
                }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: "#1e1a35"
                PathSvg {
                    path: "M-100 965 C50 950 150 960 220 935 C290 910 330 950 420 955 C500 960 540 930 600 935 "
                        + "C680 940 720 965 800 950 C880 935 950 960 1100 950 V1100 H-100 Z"
                }
            }
        }
    }
    MultiEffect {
        source: ridges
        x: -0.1 * backdrop.width
        y: -0.1 * backdrop.height
        width: ridges.width
        height: ridges.height
        transform: Scale {
            xScale: 1.2 * backdrop.width / ridges.width
            yScale: 1.2 * backdrop.height / ridges.height
        }
        blurEnabled: true
        blur: 1
        blurMax: 24
    }

    // The sun's light on the haze in front of the ridges.
    Glow { centerX: 0.63; centerY: 0.76; radiusX: 0.28; radiusY: 0.1; tint: Qt.rgba(0.82, 0.62, 0.3, 0.3) }
}
