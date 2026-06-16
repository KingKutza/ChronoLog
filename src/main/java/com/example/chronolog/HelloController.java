package com.example.chronolog;

import javafx.fxml.FXML;
import javafx.scene.canvas.Canvas;
import javafx.scene.canvas.GraphicsContext;
import javafx.scene.control.ListView;
import javafx.scene.paint.Color;
import javafx.scene.shape.ArcType;

public class HelloController {
    @FXML
    private Canvas timelineCanvas;

    @FXML
    private ListView<String> timelineList;

    @FXML
    private void initialize() {
        timelineList.getItems().setAll(
                "Prime Line",
                "Loop Candidate",
                "Secondary Archive",
                "Traveler Log",
                "Capsule Fork"
        );

        drawTimelineMockup();
    }

    private void drawTimelineMockup() {
        GraphicsContext gc = timelineCanvas.getGraphicsContext2D();
        double width = timelineCanvas.getWidth();
        double height = timelineCanvas.getHeight();

        gc.setFill(Color.web("#090b10"));
        gc.fillRoundRect(0, 0, width, height, 24, 24);
        gc.setStroke(Color.web("#2b3241"));
        gc.setLineWidth(2);
        gc.strokeRoundRect(1, 1, width - 2, height - 2, 24, 24);

        double mid = height * 0.52;
        drawArrowLine(gc, 60, mid, width - 70, mid, Color.web("#ff7a45"), 5);
        label(gc, "Prime Line", width - 210, 56, Color.web("#ff7a45"), 30);
        label(gc, "Timeline", width - 230, 104, Color.web("#f7f3e8"), 30);
        label(gc, "Secondary Archive", width - 265, height - 46, Color.web("#45f0ae"), 24);

        drawBranch(gc, 80, mid - 8, 170, 104, 300, 132, Color.web("#f7f3e8"));
        drawBranch(gc, 130, mid + 4, 270, height - 74, 420, height - 82, Color.web("#45f0ae"));
        drawBranch(gc, 420, mid - 4, 505, 178, 650, 190, Color.web("#d889ff"));
        drawBranch(gc, 700, mid + 10, 790, 158, 870, 156, Color.web("#f7f3e8"));
        drawBranch(gc, 725, mid - 2, 780, 92, 865, 76, Color.web("#f7f3e8"));

        drawLoop(gc, 226, mid - 50, 112, 50, Color.web("#ffd166"));
        drawLoop(gc, 650, mid - 55, 92, 48, Color.web("#ffd166"));
        drawLoop(gc, 685, mid - 36, 68, 36, Color.web("#ff7a45"));

        drawDrop(gc, 115, 112, height - 58, Color.web("#f7f3e8"));
        drawDrop(gc, 410, 112, height - 96, Color.web("#45f0ae"));
        drawDrop(gc, 760, 132, height - 70, Color.web("#f7f3e8"));
        drawDrop(gc, 830, 112, height - 116, Color.web("#f7f3e8"));
        drawDrop(gc, 888, 112, height - 82, Color.web("#f7f3e8"));

        label(gc, "Seed", 70, mid + 34, Color.web("#9aa4b2"), 16);
        label(gc, "Change", 208, mid + 48, Color.web("#9aa4b2"), 16);
        label(gc, "Anchor", 623, mid + 48, Color.web("#9aa4b2"), 16);
        label(gc, "Forks", 796, mid + 76, Color.web("#9aa4b2"), 16);
    }

    private void drawBranch(GraphicsContext gc, double startX, double startY, double controlX, double controlY,
                            double endX, double endY, Color color) {
        gc.setStroke(color);
        gc.setLineWidth(4);
        gc.beginPath();
        gc.moveTo(startX, startY);
        gc.quadraticCurveTo(controlX, controlY, endX, endY);
        gc.stroke();
    }

    private void drawLoop(GraphicsContext gc, double x, double y, double width, double height, Color color) {
        gc.setStroke(color);
        gc.setLineWidth(4);
        gc.strokeArc(x, y, width, height, 200, -300, ArcType.OPEN);
        drawArrowLine(gc, x + 18, y + height - 4, x + 4, y + height + 18, color, 4);
    }

    private void drawDrop(GraphicsContext gc, double x, double topY, double bottomY, Color color) {
        drawArrowLine(gc, x, topY, x, bottomY, color, 4);
    }

    private void drawArrowLine(GraphicsContext gc, double startX, double startY, double endX, double endY,
                               Color color, double lineWidth) {
        gc.setStroke(color);
        gc.setFill(color);
        gc.setLineWidth(lineWidth);
        gc.strokeLine(startX, startY, endX, endY);

        double angle = Math.atan2(endY - startY, endX - startX);
        double arrowLength = 18;
        double arrowAngle = Math.PI / 7;
        double x1 = endX - arrowLength * Math.cos(angle - arrowAngle);
        double y1 = endY - arrowLength * Math.sin(angle - arrowAngle);
        double x2 = endX - arrowLength * Math.cos(angle + arrowAngle);
        double y2 = endY - arrowLength * Math.sin(angle + arrowAngle);
        gc.fillPolygon(new double[]{endX, x1, x2}, new double[]{endY, y1, y2}, 3);
    }

    private void label(GraphicsContext gc, String text, double x, double y, Color color, int size) {
        gc.setFill(color);
        gc.setFont(javafx.scene.text.Font.font("Segoe UI", javafx.scene.text.FontWeight.BOLD, size));
        gc.fillText(text, x, y);
    }
}
