object Form23: TForm23
  Left = 0
  Top = 0
  Caption = 'GUI Emulator'
  ClientHeight = 235
  ClientWidth = 897
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object lbl1: TLabel
    Left = 764
    Top = 176
    Width = 69
    Height = 15
    Caption = 'Status Server'
  end
  object lbl2: TLabel
    Left = 502
    Top = 207
    Width = 88
    Height = 15
    Caption = 'Data: not loaded'
    ParentShowHint = False
    ShowHint = True
  end
  object btn1: TButton
    Left = 8
    Top = 168
    Width = 241
    Height = 25
    Caption = 'Start'
    TabOrder = 0
    OnClick = btn1Click
  end
  object btn2: TButton
    Left = 255
    Top = 168
    Width = 241
    Height = 25
    Caption = 'Stop'
    TabOrder = 1
    OnClick = btn2Click
  end
  object mmo1: TMemo
    Left = 8
    Top = 8
    Width = 881
    Height = 154
    TabOrder = 2
  end
  object btn3: TButton
    Left = 502
    Top = 168
    Width = 241
    Height = 25
    Caption = 'Open Client'
    TabOrder = 3
    OnClick = btn3Click
  end
  object btn4: TButton
    Left = 8
    Top = 202
    Width = 241
    Height = 25
    Caption = 'Reload data'
    TabOrder = 4
    OnClick = btn4Click
  end
end
