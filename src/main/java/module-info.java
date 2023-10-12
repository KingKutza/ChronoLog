module com.example.chronolog {
    requires javafx.controls;
    requires javafx.fxml;


    opens com.example.chronolog to javafx.fxml;
    exports com.example.chronolog;
}