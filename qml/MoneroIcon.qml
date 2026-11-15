// A ring with an M, drawn as paths so the icon stays recolorable at runtime.
import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property real size: 14
  property color iconColor: "white"
  property real strokeWidth: 2

  implicitWidth: size
  implicitHeight: size

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    transformOrigin: Item.TopLeft
    scale: root.size / 24

    ShapePath {
      strokeWidth: root.strokeWidth
      strokeColor: root.iconColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M12 2 a10 10 0 1 0 0 20 a10 10 0 1 0 0 -20 z" }
    }
    ShapePath {
      strokeWidth: root.strokeWidth
      strokeColor: root.iconColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M7.5 16 v-7.5 l4.5 4.5 l4.5 -4.5 v7.5" }
    }
  }
}
