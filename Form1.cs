namespace ChronoLog;

public partial class Form1 : Form{
    public Form1(){
        InitializeComponent();
        this.BackgroundImage = Image.FromFile("Assets/bak.png");
        this.BackgroundImageLayout = ImageLayout.Stretch;
        this.Shown += CreateViewSelector;
    }
    private void CreateViewSelector(object sender, EventArgs e){
        int ButtonWidth = 100;
        int ButtonHeight =30;
        int Spacing = 10;
        int StartingX = 20;
        int YPosition = 50;
        String[] ButtonText = {"Day","Week","Month","Year","Decade","Century"};

        for (int i=0;i<6;i++){
            Button button = new Button();
            this.Controls.Add(button);
            button.Text = ButtonText[i];
            button.Size = new System.Drawing.Size(ButtonWidth,ButtonHeight);
            button.Location = new System.Drawing.Point(StartingX + ((ButtonWidth+Spacing) * i), YPosition);
        }
    }
}
