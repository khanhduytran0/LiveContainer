#pragma once

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <sys/mman.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <libgen.h>
#include <limits.h>
#include <ftw.h>
#include <math.h>
#include <assert.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>

#include <set>
#include <map>
#include <vector>
#include <string>
#include <iostream>
using namespace std;

#define LE(x) _Swap(x)
#define BE(x) _Swap(x)

#if !defined(S_ISREG) && defined(S_IFMT) && defined(S_IFREG)
#define S_ISREG(m) (((m)&S_IFMT) == S_IFREG)
#endif

uint16_t _Swap(uint16_t value);
uint32_t _Swap(uint32_t value);
uint64_t _Swap(uint64_t value);

bool ReadFile(const char *szFile, string &strData);
bool ReadFile(string &strData, const char *szFormatPath, ...);
bool WriteFile(const char *szFile, const string &strData);
bool WriteFile(const char *szFile, const char *szData, size_t sLen);
bool WriteFile(string &strData, const char *szFormatPath, ...);
bool WriteFile(const char *szData, size_t sLen, const char *szFormatPath, ...);
bool AppendFile(const char *szFile, const string &strData);
bool AppendFile(const char *szFile, const char *szData, size_t sLen);
bool AppendFile(const string &strData, const char *szFormatPath, ...);
bool IsRegularFile(const char *szFile);
bool IsFolder(const char *szFolder);
bool IsFolderV(const char *szFormatPath, ...);
bool CreateFolder(const char *szFolder);
bool CreateFolderV(const char *szFormatPath, ...);
bool RemoveFile(const char *szFile);
bool RemoveFileV(const char *szFormatPath, ...);
bool RemoveFolder(const char *szFolder);
bool RemoveFolderV(const char *szFormatPath, ...);
bool IsFileExists(const char *szFile);
bool IsFileExistsV(const char *szFormatPath, ...);
int64_t GetFileSize(int fd);
int64_t GetFileSize(const char *szFile);
int64_t GetFileSizeV(const char *szFormatPath, ...);
string GetFileSizeString(const char *szFile);
bool IsZipFile(const char *szFile);
string GetCanonicalizePath(const char *szPath);
void *MapFile(const char *path, size_t offset, size_t size, size_t *psize, bool ro);
bool IsPathSuffix(const string &strPath, const char *suffix);

const char *StringFormat(string &strFormat, const char *szFormatArgs, ...);
string &StringReplace(string &context, const string &from, const string &to);
void StringSplit(const string &src, const string &split, vector<string> &dest);

string FormatSize(int64_t size, int64_t base = 1024);
time_t GetUnixStamp();
uint64_t GetMicroSecond();
bool SystemExec(const char *szFormatCmd, ...);
uint32_t ByteAlign(uint32_t uValue, uint32_t uAlign);

enum
{
    E_SHASUM_TYPE_1 = 1,
    E_SHASUM_TYPE_256 = 2,
};

bool SHASum(int nSumType, uint8_t *data, size_t size, string &strOutput);
bool SHASum(int nSumType, const string &strData, string &strOutput);
bool SHASum(const string &strData, string &strSHA1, string &strSHA256);
bool SHA1Text(const string &strData, string &strOutput);
bool SHASumFile(const char *szFile, string &strSHA1, string &strSHA256);
bool SHASumBase64(const string &strData, string &strSHA1Base64, string &strSHA256Base64);
bool SHASumBase64File(const char *szFile, string &strSHA1Base64, string &strSHA256Base64);
void PrintSHASum(const char *prefix, const uint8_t *hash, uint32_t size, const char *suffix = "\n");
void PrintSHASum(const char *prefix, const string &strSHASum, const char *suffix = "\n");
void PrintDataSHASum(const char *prefix, int nSumType, const string &strData, const char *suffix = "\n");
void PrintDataSHASum(const char *prefix, int nSumType, uint8_t *data, size_t size, const char *suffix = "\n");

class ZBuffer
{
public:
    ZBuffer();
    ~ZBuffer();

public:
    char *GetBuffer(uint32_t uSize);

private:
    void Free();

private:
    char *m_pData;
    uint32_t m_uSize;
};

class ZTimer
{
public:
    ZTimer();

public:
    uint64_t Reset();
    uint64_t Print(const char *szFormatArgs, ...);
    uint64_t PrintResult(bool bSuccess, const char *szFormatArgs, ...);

private:
    uint64_t m_uBeginTime;
};

class ZLog
{
public:
    enum eLogType
    {
        E_NONE = 0,
        E_ERROR = 1,
        E_WARN = 2,
        E_INFO = 3,
        E_DEBUG = 4
    };

public:
    static bool IsDebug();
    static void Print(const char *szLog);
    static void PrintV(const char *szFormatArgs, ...);
    static void Debug(const char *szLog);
    static void DebugV(const char *szFormatArgs, ...);
    static bool Warn(const char *szLog);
    static bool WarnV(const char *szFormatArgs, ...);
    static bool Error(const char *szLog);
    static bool ErrorV(const char *szFormatArgs, ...);
    static bool Success(const char *szLog);
    static bool SuccessV(const char *szFormatArgs, ...);
    static bool PrintResult(bool bSuccess, const char *szLog);
    static bool PrintResultV(bool bSuccess, const char *szFormatArgs, ...);
    static void Print(int nLevel, const char *szLog);
    static void PrintV(int nLevel, const char *szFormatArgs, ...);
    static void SetLogLever(int nLogLevel);
    static vector<std::string> logs;

private:
    static int g_nLogLevel;
	static void writeToLogFile(const std::string& message);

};
