{
   Double Commander Components
   -------------------------------------------------------------------------
   Extended ComboBox classes

   Copyright (C) 2012 Przemyslaw Nagay (cobines@gmail.com)
   Copyright (C) 2015 Alexander Koblov (alexx2000@mail.ru)

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of the
   License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   General Public License for more details.

   You should have received a copy of the GNU General Public License
   in a file called COPYING along with this program; if not, write to
   the Free Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
   02139, USA.
}

unit KASComboBox;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LResources, Forms, Controls, Graphics, Dialogs, StdCtrls;

type

  { TComboBoxWithDelItems }

  {en
     Combo box that allows removing items with Shift+Delete.
  }
  TComboBoxWithDelItems = class(TComboBox)
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  end;

  { TComboBoxAutoWidth }

  TComboBoxAutoWidth = class(TComboBox)
  protected
    procedure CalculatePreferredSize(
                         var PreferredWidth, PreferredHeight: Integer;
                         WithThemeSpace: Boolean); override;
    procedure CalculateSize(MaxWidth: Integer;
                            var NeededWidth, NeededHeight: Integer);
  end;

procedure Register;

implementation

uses
  LCLType, LCLIntf;

procedure Register;
begin
  RegisterComponents('KASComponents',[TComboBoxWithDelItems, TComboBoxAutoWidth]);
end;

{ TComboBoxWithDelItems }

procedure TComboBoxWithDelItems.KeyDown(var Key: Word; Shift: TShiftState);
var
  Index: Integer;
begin
  if DroppedDown and (Key = VK_DELETE) and (Shift = [ssShift]) then
  begin
    Index := ItemIndex;
    if (Index >= 0) and (Index < Items.Count) then
    begin
      Items.Delete(Index);
      ItemIndex := Index;
      Key := 0;
    end;
  end;
  inherited KeyDown(Key, Shift);
end;

{ TComboBoxAutoWidth }

procedure TComboBoxAutoWidth.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  AWidth: Integer;
begin
  inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);

  if csDesigning in ComponentState then Exit;

  if (Parent = nil) or (not Parent.HandleAllocated) then Exit;

  AWidth := Constraints.MinMaxWidth(10000);
  CalculateSize(AWidth, PreferredWidth, PreferredHeight);
end;

procedure TComboBoxAutoWidth.CalculateSize(MaxWidth: Integer; var NeededWidth,
  NeededHeight: Integer);
var
  DC: HDC;
  R: TRect;
  I, M: Integer;
  Flags: Cardinal;
  OldFont: HGDIOBJ;
  LabelText: String;
  Idx: Integer = -1;
begin
  if Items.Count = 0 then
    LabelText:= Text
  else begin
    M := Canvas.TextWidth(Text);
    for I := 0 to Items.Count - 1 do
    begin
      Flags := Canvas.TextWidth(Items[I]);
      if Flags > M then
      begin
        M := Flags;
        Idx := I;
      end;
    end;
    if Idx < 0 then
      LabelText := Text
    else begin
      LabelText := Items[Idx];
    end;
  end;

  if LabelText = '' then begin
    NeededWidth := 1;
    NeededHeight := 1;
    Exit;
  end;

  DC := GetDC(Parent.Handle);
  try
    R := Rect(0, 0, MaxWidth, 10000);
    OldFont := SelectObject(DC, HGDIOBJ(Font.Reference.Handle));
    Flags := DT_CALCRECT or DT_EXPANDTABS;

    DrawText(DC, PChar(LabelText), Length(LabelText), R, Flags);
    SelectObject(DC, OldFont);
    NeededWidth := R.Right - R.Left + GetSystemMetrics(SM_CXVSCROLL) * 2;
    NeededHeight := R.Bottom - R.Top;
    // DebugLn(['TComboBoxAutoWidth.CalculatePreferredSize ',DbgSName(Self),' R=',dbgs(R),' MaxWidth=',MaxWidth,' DT_WORDBREAK=',(DT_WORDBREAK and Flags)>0,' LabelText="',LabelText,'"']);
  finally
    ReleaseDC(Parent.Handle, DC);
  end;
end;

end.
