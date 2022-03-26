unit Main;

{$mode objfpc}{$H+}

{$IFDEF DARWIN}
   {$modeswitch objectivec1}
{$ENDIF}

interface

uses

  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Zipper, LCLType,

  {$IFDEF DARWIN}
  CocoaAll, CocoaUtils,
  {$ENDIF}

  StdCtrls, ExtCtrls, uos_flat;

type

  { TForm1 }

  TForm1 = class(TForm)
    gameBG1: TImage;
    gameBG2: TImage;
    groundImg1: TImage;
    groundImg2: TImage;
    personImg: TImage;
    menuBG: TImage;
    startBtn: TButton;
    phTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: char);
    procedure FormResize(Sender: TObject);
    procedure startBtnClick(Sender: TObject);
    procedure phTimerTimer(Sender: TObject);
  private
  public
  end;

  // Класс персонажа
  THuman = class
    v_X, v_Y : Single;                      // Скорость персонажа
    global_X, global_Y : Integer;            // Глобальные координаты персонажа

  end;

  // Класс потока для панарамы меню
  TPamoramImage = class(TThread)
  private
    ImageNewPos : Integer;
  protected
    procedure Execute; override;
    procedure MoveBG;
  end;

const
  KeyKick = 0.3;       // Скорость, которую дает нажатие на клавишу
  MaxHumanRun = 4;     // Максимальная скорость бега
  g = 10;
var
  Form1: TForm1;                   // Главная форма
  TMPDir : String;                 // Временная директория
  UOS_Lib_Check : Boolean;         // Наличие аудио библиотеки
  PamoramImage : TPamoramImage;    // Перемещатель панорамы в меню
  isMenuState : Boolean = False;   // Открыто ли меню игры
  isGameState : Boolean = False;   // Запущена ли игра
  Human : THuman;                  // Объект класса персонажа
  Sprite_L, Sprite_R : Integer;    // Левая и правая границы перемещения игрока
  PanoramInUse: Boolean = False;   // Работает ли панорама

implementation

{$R *.lfm}

{ TForm1 }

//
//
//   РАБОТА С РЕСУРСАМИ
//
//

// Удаление рекурсивное директории
procedure DeleteDirectory(const Name: string);
var
  F: TSearchRec;
begin
  if FindFirst(Name + '\*', faAnyFile, F) = 0 then begin
    try
      repeat
        if (F.Attr and faDirectory <> 0) then begin
          if (F.Name <> '.') and (F.Name <> '..') then begin
            DeleteDirectory(Name + '\' + F.Name);
          end;
        end else begin
          DeleteFile(Name + '\' + F.Name);
        end;
      until FindNext(F) <> 0;
    finally
      FindClose(F);
    end;
    RemoveDir(Name);
  end;
end;

// Создание временной папки
procedure CreateTMPDir();
var
  Path : String;
begin
  Path := GetTempDir();

  // В маке директория с временными файлами запрашивается через... ухо
  {$IFDEF DARWIN}
    Path := NSStringToString(NSBundle.mainBundle.resourcePath) + PathDelim;
  {$ENDIF}

  Path := Path + 'Platformer';

  DeleteDirectory(Path);

  if (CreateDir(Path)) then
     TMPDir := Path + DirectorySeparator
  else
  begin
     TMPDir := 'Platformer';
     if not CreateDir(TMPDir) then
     begin
        {$IFNDEF DARWIN}
        ShowMessage('Can''t create temp folder');
        Application.Terminate;
        {$ENDIF}
        {$IFDEF DARWIN}
        TMPDir := Path + DirectorySeparator;
        {$ENDIF}
     end else
         TMPDir := TMPDir + DirectorySeparator;
  end;
end;

// Процедура распаковки библиотек
procedure UnpackLibs();
var
  S: TResourceStream;
  UnZipper: TUnZipper;
  LibPath : String;
  AlreadyCreated : Boolean = False; // Уже распаковано
begin
     // Создание директории бибдлиотек
     LibPath := TMPDir + 'libs';
     if not CreateDir(LibPath) then
     begin
        {$IFNDEF DARWIN}
        ShowMessage('Can''t create lib folder');
        Application.Terminate;
        {$ENDIF}
        AlreadyCreated := True;
     end;

     // Если файлы не распаковывали
     if not (AlreadyCreated)  then
     begin
       // UOS
       S := TResourceStream.Create(HInstance, 'UOS', RT_RCDATA);
       S.SaveToFile(TMPDir + 'uos.zip');
       S.Free;

      UnZipper := TUnZipper.Create;
      UnZipper.FileName := TMPDir + 'uos.zip';
      UnZipper.OutputPath := LibPath;
      UnZipper.Examine;
      UnZipper.UnZipAllFiles;
      UnZipper.Free;
      DeleteFile(TMPDir + 'uos.zip');
     end;
end;

// Процедура распаковки ассетов
procedure UnpackAssets();
var
  S: TResourceStream;
  UnZipper: TUnZipper;
  AssetsPath : String;
  AlreadyCreated : Boolean = False; // Уже распаковано
begin
     // Создание директории ассетов
     AssetsPath := TMPDir + 'assets';
     if not CreateDir(AssetsPath) then
     begin
        {$IFNDEF DARWIN}
        ShowMessage('Can''t create assets folder');
        Application.Terminate;
        {$ENDIF}
        AlreadyCreated := True;
     end;

    // Если файлы не распаковывали
    if not (AlreadyCreated)  then
    begin
      // Распаковка ассетов
      S := TResourceStream.Create(HInstance, 'ASSETS', RT_RCDATA);
      S.SaveToFile(TMPDir + 'assets.zip');
      S.Free;

      UnZipper := TUnZipper.Create;
      UnZipper.FileName := TMPDir + 'ASSETS.zip';
      UnZipper.OutputPath := AssetsPath;
      UnZipper.Examine;
      UnZipper.UnZipAllFiles;
      UnZipper.Free;
      DeleteFile(TMPDir + 'ASSETS.zip');
    end;
end;

//
//
//   РАБОТА С БИБЛИОТЕКАМИ
//
//

// Загрузка библиотек
procedure LoadLibs();
var
  LibPath : String;
  PA, SF, MP : String;
  Check : Integer;

begin

    LibPath := TMPDir + 'libs';

    // Построение путей
    {$IFDEF Windows}
       {$if defined(cpu64)}
            PA := LibPath + DirectorySeparator + 'uos\Windows\64bit\LibPortaudio-64.dll';
            SF := LibPath + DirectorySeparator + 'uos\Windows\64bit\LibSndFile-64.dll';
            MP := LibPath + DirectorySeparator + 'uos\Windows\64bit\LibMpg123-64.dll';
       {$else}
            PA := LibPath + DirectorySeparator + 'uos\Windows\32bit\LibPortaudio-32.dll';
            SF := LibPath + DirectorySeparator + 'uos\Windows\32bit\LibSndFile-32.dll';
            MP := LibPath + DirectorySeparator + 'uos\Windows\32bit\LibMpg123-32.dll';
         {$endif}
     {$ENDIF}

     {$if defined(CPUAMD64) and defined(linux) }
        PA := LibPath + DirectorySeparator + 'uos/Linux/64bit/LibPortaudio-64.so';
        SF := LibPath + DirectorySeparator + 'uos/Linux/64bit/LibSndFile-64.so';
        MP := LibPath + DirectorySeparator + 'uos/Linux/64bit/LibMpg123-64.so';
     {$ENDIF}

     {$if defined(cpu86) and defined(linux)}
        PA := LibPath + DirectorySeparator + 'uos/Linux/32bit/LibPortaudio-32.so';
        SF := LibPath + DirectorySeparator + 'uos/Linux/32bit/LibSndFile-32.so';
        MP := LibPath + DirectorySeparator + 'uos/Linux/32bit/LibMpg123-32.so';
     {$ENDIF}

     {$if defined(linux) and defined(cpuaarch64)}
        PA := LibPath + DirectorySeparator + 'uos/Linux/aarch64_raspberrypi/libportaudio_aarch64.so';
        SF := LibPath + DirectorySeparator + 'uos/Linux/aarch64_raspberrypi/libsndfile_aarch64.so';
        MP := LibPath + DirectorySeparator + 'uos/Linux/aarch64_raspberrypi/libmpg123_aarch64.so';
     {$ENDIF}

     {$if defined(linux) and defined(cpuarm)}
        PA := LibPath + DirectorySeparator + 'uos/Linux/arm_raspberrypi/libportaudio-arm.so';
        SF := LibPath + DirectorySeparator + 'uos/Linux/arm_raspberrypi/libsndfile-arm.so';
        MP := LibPath + DirectorySeparator + 'uos/Linux/arm_raspberrypi/libmpg123-arm.so';
     {$ENDIF}

     {$IFDEF freebsd}
        {$if defined(cpu64)}
          PA := LibPath + DirectorySeparator + 'uos/FreeBSD/64bit/libportaudio-64.so';
          SF := LibPath + DirectorySeparator + 'uos/FreeBSD/64bit/libsndfile-64.so';
          MP := LibPath + DirectorySeparator + 'uos/FreeBSD/64bit/libmpg123-64.so';
        {$else}
          PA := LibPath + DirectorySeparator + 'uos/FreeBSD/32bit/libportaudio-32.so';
          SF := LibPath + DirectorySeparator + 'uos/FreeBSD/32bit/libsndfile-32.so';
          MP := LibPath + DirectorySeparator + 'uos/FreeBSD/32bit/libmpg123-32.so';
        {$endif}
     {$ENDIF}

     {$IFDEF Darwin}
        {$IFDEF CPU32}
          PA := LibPath + DirectorySeparator + 'uos/Mac/32bit/LibPortaudio-32.dylib';
          SF := LibPath + DirectorySeparator + 'uos/Mac/32bit/LibSndFile-32.dylib';
          MP := LibPath + DirectorySeparator + 'uos/Mac/32bit/LibMpg123-32.dylib';
        {$ENDIF}

        {$IFDEF CPU64}
          PA := LibPath + DirectorySeparator + 'uos/lib/Mac/64bit/LibPortaudio-64.dylib';
          SF := LibPath + DirectorySeparator + 'uos/lib/Mac/64bit/LibSndFile-64.dylib';
          MP := LibPath + DirectorySeparator + 'uos/lib/Mac/64bit/LibMpg123-64.dylib';
        {$ENDIF}
     {$ENDIF}

     // Загрузка UOS
     Check := uos_LoadLib(Pchar(PA), Pchar(SF), Pchar(MP), nil, nil, nil);
     if Check = 0 then
        UOS_Lib_Check := true
     else
     begin
       // Если не нашел библиотеки кастомные - пробуем системные
       Check := uos_LoadLib('system', 'system', nil, nil, nil, nil);
       UOS_Lib_Check := (Check = 0);
     end;
end;

//
//
//   РАБОТА С АУДИО
//
//

// Начать проигрывание фоновой музыки
procedure PlayMusicBG();
begin
     if UOS_Lib_Check then
     begin
       uos_CreatePlayer(0);
       uos_AddFromFile(0, PChar(TMPDir + 'assets' + DirectorySeparator + 'sound' + DirectorySeparator + 'bg_sound.ogg'));

       {$if defined(cpuarm) or defined(cpuaarch64)}  // need a lower latency
          uos_AddIntoDevOut(0, -1, 0.3, -1, -1, -1, -1, -1);
       {$else}
          uos_AddIntoDevOut(0, -1, -1, -1, -1, -1, -1, -1);
       {$endif}
       uos_Play(0, MAXINT);
     end;
end;

//
//
//   РАБОТА С ГРАФИКОЙ
//
//

// Первичная подгонка зависимых изображений
procedure FirstRepaint();
begin
     Form1.gameBG2.Top := Form1.gameBG1.Top;
     Form1.gameBG2.Left := Form1.gameBG1.Left + Form1.gameBG1.Width;

     Form1.groundImg2.Top := Form1.groundImg1.Top;
     Form1.groundImg2.Left := Form1.groundImg1.Left + Form1.groundImg1.Width;
end;

// Настройка геометрии графических объектов
procedure ReapaintOnResize();
begin
     // Перерисовка геометрии кнопок
     Form1.startBtn.Width := Form1.Width div 3;
     Form1.startBtn.Height:= Form1.Height div 10;
     Form1.startBtn.Left := Form1.Width div 3;
     Form1.startBtn.Top := (Form1.Height div 10) * 2 * 1;

     // Перерисовка изображения панорамы в меню
     Form1.menuBG.Height := Form1.Height;
     Form1.menuBG.Width := Form1.menuBG.Height * 3;
     Form1.menuBG.Repaint;

     // Перерисовка фонового изображения в игре
     Form1.gameBG1.Height := Form1.Height;
     Form1.gameBG1.Width := Form1.gameBG1.Height * 3;
     Form1.gameBG2.Height := Form1.gameBG1.Height;
     Form1.gameBG2.Width := Form1.gameBG1.Width;

     // Убираем ямы при перерисовке
     if (Form1.gameBG1.Left < Form1.gameBG2.Left) then
        Form1.gameBG2.Left := Form1.gameBG1.Left + Form1.gameBG1.Width
     else
        Form1.gameBG1.Left := Form1.gameBG2.Left + Form1.gameBG2.Width;

     // Перерисовка нижней поверхности в игре
     Form1.groundImg1.Height:= Form1.Height div 4;
     Form1.groundImg1.Width:= Form1.groundImg1.Height * 8;
     Form1.groundImg1.Top:= Form1.Height - Form1.groundImg1.Height;

     Form1.groundImg2.Height := Form1.groundImg1.Height;
     Form1.groundImg2.Width := Form1.groundImg1.Width;
     Form1.groundImg2.Top := Form1.groundImg1.Top;

     // Убираем ямы при перерисовке
     if (Form1.groundImg1.Left < Form1.groundImg2.Left) then
        Form1.groundImg2.Left := Form1.groundImg1.Left + Form1.groundImg1.Width
     else
        Form1.groundImg1.Left := Form1.groundImg2.Left + Form1.groundImg2.Width;



     // Перерисовка персонажа
     // Считаем землю равной 2м блокам
     Form1.personImg.Height:= Form1.groundImg1.Height;
     Form1.personImg.Width:= Round(Form1.personImg.Height / 1.275); // Округляем, чтобы точнее сохранить пропорции персонажа
     Form1.personImg.Top := Form1.groundImg1.Top - Form1.personImg.Height;

     // Установка границ перемещения
     Sprite_L := Form1.Width div 3;
     Sprite_R := Sprite_L * 2;

end;

// Перемещение камеры
procedure MoveCamera(offset : Integer);
begin
     // Двигаем фон
     Form1.gameBG1.Left:=Form1.gameBG1.Left - offset;
     Form1.gameBG2.Left:=Form1.gameBG2.Left - offset;

     if (offset > 0) then // Если камера двигается вправа
     begin
       if (Form1.gameBG1.Left + Form1.gameBG1.Width < 0) then
          Form1.gameBG1.Left := Form1.gameBG2.Left + Form1.gameBG2.Width
       else
       if (Form1.gameBG2.Left + Form1.gameBG2.Width < 0) then
          Form1.gameBG2.Left := Form1.gameBG1.Left + Form1.gameBG1.Width;
     end else
     if (offset < 0) then // Если камера двигается влево
     begin
       if (Form1.gameBG1.Left > Form1.Width) then
          Form1.gameBG1.Left := Form1.gameBG2.Left - Form1.gameBG1.Width
       else
       if (Form1.gameBG2.Left  > Form1.Width) then
          Form1.gameBG2.Left := Form1.gameBG1.Left - Form1.gameBG2.Width;
     end;

     // Двигаем нижнюю часть
     Form1.groundImg1.Left:=Form1.groundImg1.Left - offset;
     Form1.groundImg2.Left:=Form1.groundImg2.Left - offset;

     if (offset > 0) then // Если камера двигается вправа
     begin
       if (Form1.groundImg1.Left + Form1.groundImg1.Width < 0) then
          Form1.groundImg1.Left := Form1.groundImg2.Left + Form1.groundImg2.Width
       else
       if (Form1.groundImg2.Left + Form1.groundImg2.Width < 0) then
          Form1.groundImg2.Left := Form1.groundImg1.Left + Form1.groundImg1.Width;
     end else
     if (offset < 0) then // Если камера двигается влево
     begin
       if (Form1.groundImg1.Left > Form1.Width) then
          Form1.groundImg1.Left := Form1.groundImg2.Left - Form1.groundImg1.Width
       else
       if (Form1.groundImg2.Left  > Form1.Width) then
          Form1.groundImg2.Left := Form1.groundImg1.Left - Form1.groundImg2.Width;
     end;

end;

// Запуск панорамы в меню
procedure StartMenuPanoram();
begin
     Form1.menuBG.Picture.LoadFromFile(TMPDir
                                       + 'assets' + DirectorySeparator
                                       + 'textures' + DirectorySeparator
                                       + 'menu_bg.jpg');
     PanoramInUse := True;
     PamoramImage := TPamoramImage.Create(False);
end;

//
//
//   РАБОТА С ИГРОВЫМ ПРОЦЕССОМ
//
//

// Запуск игры
procedure StartGame();
begin
     // Отрисовка фона
     Form1.gameBG1.Picture.LoadFromFile(TMPDir +  DirectorySeparator
                                       + 'assets' + DirectorySeparator
                                       + 'textures' + DirectorySeparator
                                       + 'game_bg.jpg');
     Form1.gameBG2.Picture := Form1.gameBG1.Picture;
     Form1.gameBG1.Visible := True;
     Form1.gameBG2.Visible := Form1.gameBG1.Visible;

     // Отрисовка нижней поверхности
     Form1.groundImg1.Picture.LoadFromFile(TMPDir +  DirectorySeparator
                                       + 'assets' + DirectorySeparator
                                       + 'textures' + DirectorySeparator
                                       + 'ground.png');
     Form1.groundImg2.Picture := Form1.groundImg1.Picture;
     Form1.groundImg1.Visible := True;
     Form1.groundImg2.Visible := Form1.groundImg1.Visible;

     // Отрисовка персонажа
     Form1.personImg.Picture.LoadFromFile(TMPDir +  DirectorySeparator
                                       + 'assets' + DirectorySeparator
                                       + 'textures' + DirectorySeparator
                                       + 'person.png');
     Form1.personImg.Visible := True;

     // Создаем персонажа
     Human := THuman.Create;
     Human.v_X:=0;
     Human.v_Y:=0;
     Human.global_X:=0;
     Human.global_Y:=0;


     // Включаем режим игры
     isGameState := True;

     // Запускаем поток обработки физики
     Form1.phTimer.Enabled:=True;


end;

//
//
//   РАБОТА С ФОРМОЙ
//
//

// Открытие меню
procedure StartMenu();
begin
     // Отображение фона и кнопок
     Form1.menuBG.Visible:=True;
     Form1.startBtn.Visible:=True;

     // Перевод состояния
     isMenuState := True;
end;

// Закрытие меню
procedure CloseMenu();
begin
     // Отображение фона и кнопок
     Form1.menuBG.Visible:=False;
     Form1.startBtn.Visible:=False;

     // Перевод состояния
     isMenuState := False;

     // Отключаем панораму
     PanoramInUse := False;
end;

// Событие при запуске программы
procedure TForm1.FormCreate(Sender: TObject);
begin
     // Распаковка ресурсов приожения
     CreateTMPDir();
     UnpackLibs();
     UnpackAssets();

     // Загрузка библиотек
     LoadLibs();

     // Запуск музыки
     PlayMusicBG();

     // Первичная подгонка зависимых изображений
     FirstRepaint();

     // Настройка геометрии графических объектов
     ReapaintOnResize();

     // Запускаем меню
     StartMenu();

     // Загрузка панорамы меню
     StartMenuPanoram();
end;

// Событие при изменении размеров формы
procedure TForm1.FormResize(Sender: TObject);
begin
     // Настройка геометрии графических объектов
     ReapaintOnResize();
end;

// Нажата кнопка начала игры
procedure TForm1.startBtnClick(Sender: TObject);
begin
     // Закрываем меню
     CloseMenu();

     // Запускаем игру
     StartGame();

end;

// Физический движок
// Работаем с таймером, чтобы иметь привязку по времени
procedure TForm1.phTimerTimer(Sender: TObject);
var
   local_X, local_Y : Integer;   // Локальные координаты персонажа
begin
     if (Human.v_X <> 0.0) then
     begin
          local_X := Form1.personImg.Left + Round(Human.v_X * 1000 / Form1.phTimer.Interval);
          Human.global_X:=Human.global_X + Round(Human.v_X * 1000 / Form1.phTimer.Interval);
          // Отрисовка
          if (local_X > Sprite_R) then
          begin
               MoveCamera(local_X - Sprite_R);
               Form1.personImg.Left := Sprite_R;
          end
          else if (local_X < Sprite_L - Form1.personImg.Width) then
          begin
               MoveCamera(local_X - Sprite_L + Form1.personImg.Width);
               Form1.personImg.Left := Sprite_L - Form1.personImg.Width;
          end else
               Form1.personImg.Left := local_X;

          // Естественное торможение
          if (Human.v_X > 0.0) then
          begin
               Human.v_X := Human.v_X - (KeyKick * 0.25);
               if (Human.v_X < 0) then
                  Human.v_X := 0.0; // Финальная остановка
               end
               else
               begin
                  Human.v_X := Human.v_X + (KeyKick * 0.25);
                  if (Human.v_X > 0) then
                     Human.v_X := 0.0; // Финальная остановка
               end;
          end;

          if (Human.v_Y < 0) then
          begin
            //Human.v_Y := Human.v_Y - Round( g * Form1.phTimer.Interval/1000);
            // local_Y := Form1.personImg.Top - Human.v_Y * Form1.phTimer.Interval ;
            //Form1.personImg.Top := local_Y;
            //if (Form1.personImg.Top - Form1.personImg.Height > Form1.groundImg1.Top ) then
            //  begin
            //     Form1.personImg.Top - Form1.personImg.Height = Form1.groundImg1.Top;
            //   end;
           end;
end;

//
//
//   РАБОТА С СОБЫТИЯМИ
//
//

// При зажатии клавиши
// ВАЖНО!!! В Lazarus данное событие постоянно циклично выполняется, пока нажата клавиша
procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
     // ВАЖНО!!! Т.к. можно нажать одновременно вправо и влево - лучше отказаться от else
     if (Key = VK_RIGHT) then
     begin
        // Ограничитель скорости
        if (MaxHumanRun >= Human.v_X + KeyKick) then
           Human.v_X := Human.v_X + KeyKick
        else
            Human.v_X := MaxHumanRun;
     end;

     if (Key = VK_LEFT) then
     begin
          // Ограничитель скорости
          if (MaxHumanRun >= (-1)*(Human.v_X - KeyKick)) then
             Human.v_X := Human.v_X - KeyKick
          else
             Human.v_X := (-1)*MaxHumanRun;
     end;

end;

// При нажатии клавишы
procedure TForm1.FormKeyPress(Sender: TObject; var Key: Char );
begin
     // Прыжок
     if (Key = ' ' ) then
     begin
      if (Human.v_Y = 0) then // Запрет на прыжок в воздухе
         Human.v_Y :=  KeyKick;
     end;
end;

//
//
//   РАБОТА С ПОТОКАМИ
//
//

// Поток перемещения камеры панорамы
procedure TPamoramImage.Execute;
var
  way : Integer = -1; // Задает направление движения панорамы
begin
     while (PanoramInUse) do
     begin
          if (isMenuState) then
          begin
            ImageNewPos := Form1.menuBG.Left + 1 * way;
            // Чтобы не было ошибок - взаимодействие с формой через Synchronize
            Synchronize(@MoveBG);
            if (((ImageNewPos + Form1.menuBG.Width) <= Form1.Width) OR (ImageNewPos >= 0)) then
               way := way * (-1); // Меняем направление движения
          end;

         // Ждем время для медленного перемещенимя панорамы и снижения нагрузки на процессор
         Sleep(100);
     end;
end;

// Синхронный поток перемещения избражения
procedure TPamoramImage.MoveBG;
begin
     Form1.menuBG.Left := ImageNewPos;
end;


end.

