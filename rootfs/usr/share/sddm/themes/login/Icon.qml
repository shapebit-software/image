// A line icon, drawn from an SVG path on a 24 by 24 grid.
import QtQuick
import QtQuick.Shapes

Item {
    id: icon

    property string path
    property color color: Theme.text
    property real size: 18 * Theme.unit

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: icon.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: icon.color
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.path }
        }
    }
}
