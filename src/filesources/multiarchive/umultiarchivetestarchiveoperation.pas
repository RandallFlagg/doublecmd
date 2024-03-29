{
   Double commander
   -------------------------------------------------------------------------
   Archive test operation for mutiarchive manager

   Copyright (C) 2018 Alexander Koblov (alexx2000@mail.ru)

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program. If not, see <http://www.gnu.org/licenses/>.
}

unit uMultiArchiveTestArchiveOperation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  uFileSourceOperation,
  uFileSourceTestArchiveOperation,
  uFileSource,
  uFileSourceOperationUI,
  uFile,
  uMultiArchiveFileSource,
  uGlobs, uLog, un_process;

type

  { TMultiArchiveTestArchiveOperation }

  TMultiArchiveTestArchiveOperation = class(TFileSourceTestArchiveOperation)

  private
    FMultiArchiveFileSource: IMultiArchiveFileSource;
    FStatistics: TFileSourceTestArchiveOperationStatistics; // local copy of statistics
    FFullFilesTreeToTest: TFiles;  // source files including all files/dirs in subdirectories

    procedure ShowError(sMessage: String; logOptions: TLogOptions);
    procedure LogMessage(sMessage: String; logOptions: TLogOptions; logMsgType: TLogMsgType);
    procedure CheckForErrors(const FileName: String; ExitStatus: LongInt);

  protected
    FExProcess: TExProcess;
    FTempFile: String;
    FErrorLevel: LongInt;
    procedure OnReadLn(str: string);
    procedure UpdateProgress(SourceName: String; IncSize: Int64);
    procedure FileSourceOperationStateChangedNotify({%H-}Operation: TFileSourceOperation;
                                                    AState: TFileSourceOperationState);

  public
    constructor Create(aTargetFileSource: IFileSource;
                       var theFilesToDelete: TFiles); override;

    destructor Destroy; override;

    procedure Initialize; override;
    procedure MainExecute; override;
    procedure Finalize; override;

  end;

implementation

uses
  uOSUtils, DCOSUtils, uLng, uMultiArc, uMultiArchiveUtil, LCLProc;

constructor TMultiArchiveTestArchiveOperation.Create(aTargetFileSource: IFileSource;
                                              var theFilesToDelete: TFiles);
begin
  FMultiArchiveFileSource := aTargetFileSource as IMultiArchiveFileSource;
  FFullFilesTreeToTest:= nil;

  inherited Create(aTargetFileSource, theFilesToDelete);
end;

destructor TMultiArchiveTestArchiveOperation.Destroy;
begin
  FreeAndNil(FFullFilesTreeToTest);
  inherited Destroy;
end;

procedure TMultiArchiveTestArchiveOperation.Initialize;
begin
  FExProcess:= TExProcess.Create(EmptyStr);
  FExProcess.OnReadLn:= @OnReadLn;
  FExProcess.OnOperationProgress:= @CheckOperationState;
  FTempFile:= GetTempName(GetTempFolder);

  AddStateChangedListener([fsosStarting, fsosPausing, fsosStopping], @FileSourceOperationStateChangedNotify);

  // Get initialized statistics; then we change only what is needed.
  FStatistics := RetrieveStatistics;
  FStatistics.ArchiveFile:= FMultiArchiveFileSource.ArchiveFileName;

  with FMultiArchiveFileSource do
  FillAndCount('*.*', SourceFiles,
               True,
               FFullFilesTreeToTest,
               FStatistics.TotalFiles,
               FStatistics.TotalBytes);     // gets full list of files (recursive)
end;

procedure TMultiArchiveTestArchiveOperation.MainExecute;
var
  I: Integer;
  MultiArcItem: TMultiArcItem;
  aFile: TFile;
  sReadyCommand,
  sCommandLine: String;
begin
  MultiArcItem := FMultiArchiveFileSource.MultiArcItem;
  sCommandLine:= MultiArcItem.FTest;
  // Get maximum acceptable command errorlevel
  FErrorLevel:= ExtractErrorLevel(sCommandLine);
  if Pos('%F', sCommandLine) <> 0 then // test file by file
    for I:=0 to FFullFilesTreeToTest.Count - 1 do
    begin
      aFile:= FFullFilesTreeToTest[I];
      UpdateProgress(aFile.FullPath, 0);

      sReadyCommand:= FormatArchiverCommand(
                                            MultiArcItem.FArchiver,
                                            sCommandLine,
                                            FMultiArchiveFileSource.ArchiveFileName,
                                            nil,
                                            aFile.FullPath
                                            );
      OnReadLn(sReadyCommand);

      FExProcess.SetCmdLine(sReadyCommand);
      FExProcess.Execute;

      UpdateProgress(aFile.FullPath, aFile.Size);
      // Check for errors.
      CheckForErrors(aFile.FullPath , FExProcess.ExitStatus);
    end
  else  // test whole file list
    begin
      sReadyCommand:= FormatArchiverCommand(
                                            MultiArcItem.FArchiver,
                                            sCommandLine,
                                            FMultiArchiveFileSource.ArchiveFileName,
                                            FFullFilesTreeToTest,
                                            EmptyStr,
                                            EmptyStr,
                                            FTempFile
                                            );
      OnReadLn(sReadyCommand);

      FExProcess.SetCmdLine(sReadyCommand);
      FExProcess.Execute;

      // Check for errors.
      CheckForErrors(FMultiArchiveFileSource.ArchiveFileName, FExProcess.ExitStatus);
    end;
end;

procedure TMultiArchiveTestArchiveOperation.Finalize;
begin
  FreeAndNil(FExProcess);
  with FMultiArchiveFileSource.MultiArcItem do
  if not FDebug then
    mbDeleteFile(FTempFile);
end;

procedure TMultiArchiveTestArchiveOperation.ShowError(sMessage: String; logOptions: TLogOptions);
begin
  if not gSkipFileOpError then
  begin
    if AskQuestion(sMessage, '', [fsourSkip, fsourAbort],
                   fsourSkip, fsourAbort) = fsourAbort then
    begin
      RaiseAbortOperation;
    end;
  end
  else
  begin
    LogMessage(sMessage, logOptions, lmtError);
  end;
end;

procedure TMultiArchiveTestArchiveOperation.LogMessage(sMessage: String; logOptions: TLogOptions; logMsgType: TLogMsgType);
begin
  case logMsgType of
    lmtError:
      if not (log_errors in gLogOptions) then Exit;
    lmtInfo:
      if not (log_info in gLogOptions) then Exit;
    lmtSuccess:
      if not (log_success in gLogOptions) then Exit;
  end;

  if logOptions <= gLogOptions then
  begin
    logWrite(Thread, sMessage, logMsgType);
  end;
end;

procedure TMultiArchiveTestArchiveOperation.OnReadLn(str: string);
begin
  with FMultiArchiveFileSource.MultiArcItem do
  if FOutput or FDebug then
    logWrite(Thread, str, lmtInfo, True, False);
end;

procedure TMultiArchiveTestArchiveOperation.CheckForErrors(const FileName: String; ExitStatus: LongInt);
begin
  if (ExitStatus > FErrorLevel) then
    begin
      ShowError(Format(rsMsgLogError + rsMsgLogTest, [FileName + ' - ' + rsMsgExitStatusCode + ' ' + IntToStr(ExitStatus)]), [log_arc_op]);
    end
  else
    begin
      LogMessage(Format(rsMsgLogSuccess + rsMsgLogTest, [FileName]), [log_arc_op], lmtSuccess);
    end;
end;

procedure TMultiArchiveTestArchiveOperation.UpdateProgress(SourceName: String; IncSize: Int64);
begin
  with FStatistics do
  begin
    FStatistics.CurrentFile:= SourceName;

    DoneBytes := DoneBytes + IncSize;

    UpdateStatistics(FStatistics);
  end;
end;

procedure TMultiArchiveTestArchiveOperation.FileSourceOperationStateChangedNotify
  (Operation: TFileSourceOperation; AState: TFileSourceOperationState);
begin
  case AState of
    fsosStarting:
      FExProcess.Process.Resume;
    fsosPausing:
      FExProcess.Process.Suspend;
    fsosStopping:
      FExProcess.Stop;
  end;
end;

end.
