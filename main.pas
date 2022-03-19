unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Zipper, LCLType,
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
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: char);
    procedure FormResize(Sender: TObject);
    procedure startBtnClick(Sender: TObject);
  private
  public
  end;

  // Класс персонажа
  THuman = class
    v_X, v_Y : Integer;                      // Скорость персонажа
    global_X, global_Y : Integer;            // Глобальные координаты персонажа

  end;

  // Класс потока для панарамы меню
  TPamoramImage = class(TThread)
    procedure Execute; override;
  end;

  // Класс потока для панарамы меню
  TPhysicsEngine = class(TThread)
    procedure Execute; override;
  end;

const
  KeyKick = 10;        // Скорость, которую дает нажатие на клавишу

var
  Form1: TForm1;                   // Главная форма
  TMPDir : String;                 // Временная директория
  UOS_Lib_Check : Boolean;         // Наличие аудио библиотеки
  PamoramImage : TPamoramImage;    // Перемещатель панорамы в меню
  isMenuState : Boolean = False;   // Открыто ли меню игры
  isGameState : Boolean = False;   // Запущена ли игра
  Human : THuman;                  // Объект класса персонажа
  PhysicsEngine : TPhysicsEngine;  // Объект класса физического движка
  Sprite_L, Sprite_R : Integer;    // Левая и правая границы перемещения игрока

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
  Path := Path + 'Platformer';

  DeleteDirectory(Path);
  if (CreateDir(Path)) then
     TMPDir := Path
  else
  begin
     TMPDir := 'Platformer';
     if not CreateDir(Path) then
     begin
        ShowMessage('Can''t create temp folder');
        Application.Terminate;
     end;
  end;

end;

// Процедура распаковки библиотек
procedure UnpackLibs();
var
  S: TResourceStream;
  UnZipper: TUnZipper;
  LibPath : String;
begin

     // Создание директории бибдлиотек
     LibPath := TMPDir +  DirectorySeparator + 'libs';
     if not CreateDir(LibPath) then
     begin
        ShowMessage('Can''t create lib folder');
        Application.Terminate;
     end;

     // UOS
     S := TResourceStream.Create(HInstance, 'UOS', RT_RCDATA);
     S.SaveToFile(TMPDir +  DirectorySeparator + 'uos.zip');
     S.Free;

    UnZipper := TUnZipper.Create;
    UnZipper.FileName := TMPDir +  DirectorySeparator + 'uos.zip';
    UnZipper.OutputPath := LibPath;
    UnZipper.Examine;
    UnZipper.UnZipAllFiles;
    UnZipper.Free;
    DeleteFile(TMPDir +  DirectorySeparator + 'uos.zip');

end;

// Процедура распаковки ассетов
procedure UnpackAssets();
var
  S: TResourceStream;
  UnZipper: TUnZipper;
  AssetsPath : String;
begin
     // Создание директории ассетов
     AssetsPath := TMPDir +  DirectorySeparator + 'assets';
     if not CreateDir(AssetsPath) then
     begin
        ShowMessage('Can''t create assets folder');
        Application.Terminate;
     end;

    // Распаковка ассетов
    S := TResourceStream.Create(HInstance, 'ASSETS', RT_RCDATA);
    S.SaveToFile(TMPDir +  DirectorySeparator + 'assets.zip');
    S.Free;

    UnZipper := TUnZipper.Create;
    UnZipper.FileName := TMPDir +  DirectorySeparator + 'ASSETS.zip';
    UnZipper.OutputPath := AssetsPath;
    UnZipper.Examine;
    UnZipper.UnZipAllFiles;
    UnZipper.Free;
    DeleteFile(TMPDir +  DirectorySeparator + 'ASSETS.zip');
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

    LibPath := TMPDir +  DirectorySeparator + 'libs';

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
          PA := LibPath + DirectorySeparator + 'uos/Mac/64bit/LibPortaudio-64.dylib';
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
       Check := uos_LoadLib(PChar('system'), PChar('system'), PChar('system'), nil, nil, nil);
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
       uos_AddFromFile(0, PChar(TMPDir +  DirectorySeparator + 'assets' + DirectorySeparator + 'sound' + DirectorySeparator + 'bg_sound.mp3'));
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
     Form1.personImg.Width:= Round(Form1.personImg.Height / 1.7); // Округляем, чтобы точнее сохранить пропорции персонажа
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
     Form1.menuBG.Picture.LoadFromFile(TMPDir +  DirectorySeparator
                                       + 'assets' + DirectorySeparator
                                       + 'textures' + DirectorySeparator
                                       + 'menu_bg.jpg');
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
     PhysicsEngine := TPhysicsEngine.Create(False);


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
      Human.v_X:= Human.v_X + KeyKick;
     end;

     if (Key = VK_LEFT) then
     begin
      Human.v_X:= Human.v_X - KeyKick;
     end;

end;

// При нажатии клавишы
procedure TForm1.FormKeyPress(Sender: TObject; var Key: char);
begin
     // Прыжок
     if (Key = ' ') then
     begin
      if (Human.v_Y = 0)  // Запрет на прыжок в воздухе
         Human.v_Y:= KeyKick;
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
     while (True) do
     begin
          if (isMenuState) then
          begin
            Form1.menuBG.Left := Form1.menuBG.Left + 1 * way;
            if (((Form1.menuBG.Left + Form1.menuBG.Width) <= Form1.Width) OR (Form1.menuBG.Left >= 0)) then
               way := way * (-1); // Меняем направление движения
          end;

         // Ждем время для медленного перемещенимя панорамы и снижения нагрузки на процессор
         if (isMenuState) then
            Sleep(100)
         else
             Sleep(3000);
     end;
end;

// Поток работы с физикой
procedure TPhysicsEngine.Execute;
var
   local_X, local_Y : Integer;   // Локальные координаты персонажа
   acceleration : Integer = 1;   // Ускорение событий урезанием фреймрейта
begin

     // ВНИМАНИЕ!!! Т.к. в Lazarus KeyDown событие выполняется циклично - можно отказаться от ускорение по оX для повышения производительности

     while (isGameState) do
     begin
          // Преобразование скорости в перемещение
          if (Human.v_X <> 0) then
          begin
               local_X := Form1.personImg.Left + Human.v_X * acceleration;
               Human.global_X:=Human.global_X + Human.v_X * acceleration;
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
               if (Human.v_X > 0) then
               begin
                  Human.v_X := Human.v_X - Round(KeyKick * 0.25);
                  if (Human.v_X < 0) then
                     Human.v_X := 0; // Финальная остановка
               end
               else
               begin
                  Human.v_X := Human.v_X + Round(KeyKick * 0.25);
                  if (Human.v_X > 0) then
                     Human.v_X := 0; // Финальная остановка
               end;
          end;

          if (Human.v_Y <> 0) then
          begin
               // Надо подумать )))
               // Для рассчета скорости использовать Vтекущая - g*acceleration
               // Рассчитывать ускорение тоже ненужно
               // Задача на подумать и написать, в этом коды решения нет
          end;
     end;
end;


end.

