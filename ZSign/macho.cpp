#include "common/common.h"
#include "common/json.h"
#include "common/mach-o.h"
#include "openssl.h"
#include "signing.h"
#include "macho.h"
#include "Utils.hpp"

ZMachO::ZMachO()
{
	m_pBase = NULL;
	m_sSize = 0;
	m_bCSRealloced = false;
}

ZMachO::~ZMachO()
{
	FreeArchOes();
}

bool ZMachO::Init(const char *szFile)
{
	m_strFile = szFile;
	return OpenFile(szFile);
}

bool ZMachO::InitV(const char *szFormatPath, ...)
{
	char szFile[PATH_MAX] = {0};
	va_list args;
	va_start(args, szFormatPath);
	vsnprintf(szFile, PATH_MAX, szFormatPath, args);
	va_end(args);

	return Init(szFile);
}

bool ZMachO::Free()
{
	FreeArchOes();
	return CloseFile();
}

bool ZMachO::NewArchO(uint8_t *pBase, uint32_t uLength)
{
	ZArchO *archo = new ZArchO();
	if (archo->Init(pBase, uLength))
	{
		m_arrArchOes.push_back(archo);
		return true;
	}
	delete archo;
	return false;
}

void ZMachO::FreeArchOes()
{
	for (size_t i = 0; i < m_arrArchOes.size(); i++)
	{
		ZArchO *archo = m_arrArchOes[i];
		delete archo;
	}
	m_pBase = NULL;
	m_sSize = 0;
	m_arrArchOes.clear();
}

bool ZMachO::OpenFile(const char *szPath)
{
	FreeArchOes();

	m_sSize = 0;
	m_pBase = (uint8_t *)MapFile(szPath, 0, 0, &m_sSize, false);
	if (NULL != m_pBase)
	{
		uint32_t magic = *((uint32_t *)m_pBase);
		if (FAT_CIGAM == magic || FAT_MAGIC == magic)
		{
			fat_header *pFatHeader = (fat_header *)m_pBase;
			int nFatArch = (FAT_MAGIC == magic) ? pFatHeader->nfat_arch : LE(pFatHeader->nfat_arch);
			for (int i = 0; i < nFatArch; i++)
			{
				fat_arch *pFatArch = (fat_arch *)(m_pBase + sizeof(fat_header) + sizeof(fat_arch) * i);
				uint8_t *pArchBase = m_pBase + ((FAT_MAGIC == magic) ? pFatArch->offset : LE(pFatArch->offset));
				uint32_t uArchLength = (FAT_MAGIC == magic) ? pFatArch->size : LE(pFatArch->size);
				if (!NewArchO(pArchBase, uArchLength))
				{
					ZLog::ErrorV(">>> Invalid Arch File In Fat Macho File!\n");
					return false;
				}
			}
		}
		else if (MH_MAGIC == magic || MH_CIGAM == magic || MH_MAGIC_64 == magic || MH_CIGAM_64 == magic)
		{
			if (!NewArchO(m_pBase, (uint32_t)m_sSize))
			{
				ZLog::ErrorV(">>> Invalid Macho File!\n");
				return false;
			}
		}
		else
		{
			ZLog::ErrorV(">>> Invalid Macho File (2)!\n");
			return false;
		}
	}

	return (!m_arrArchOes.empty());
}

bool ZMachO::CloseFile()
{
	if (NULL == m_pBase || m_sSize <= 0)
	{
		return false;
	}

	if ((munmap((void *)m_pBase, m_sSize)) < 0)
	{
		ZLog::ErrorV(">>> CodeSign Write(munmap) Failed! Error: %p, %lu, %s\n", m_pBase, m_sSize, strerror(errno));
		return false;
	}
    refreshFile(m_strFile.c_str());
	return true;
}

void ZMachO::PrintInfo()
{
	for (size_t i = 0; i < m_arrArchOes.size(); i++)
	{
		ZArchO *archo = m_arrArchOes[i];
		archo->PrintInfo();
	}
}

bool ZMachO::Sign(ZSignAsset *pSignAsset, bool bForce, string strBundleId, string strInfoPlistSHA1, string strInfoPlistSHA256, const string &strCodeResourcesData)
{
	if (NULL == m_pBase || m_arrArchOes.empty())
	{
		return false;
	}

	for (size_t i = 0; i < m_arrArchOes.size(); i++)
	{
		ZArchO *archo = m_arrArchOes[i];
		if (strBundleId.empty())
		{
			JValue jvInfo;
			jvInfo.readPList(archo->m_strInfoPlist);
			strBundleId = jvInfo["CFBundleIdentifier"].asCString();
			if (strBundleId.empty())
			{
				strBundleId = basename((char *)m_strFile.c_str());
			}
		}

		if (strInfoPlistSHA1.empty() || strInfoPlistSHA256.empty())
		{
			if (archo->m_strInfoPlist.empty())
			{
				strInfoPlistSHA1.append(20, 0);
				strInfoPlistSHA256.append(32, 0);
			}
			else
			{
				SHASum(archo->m_strInfoPlist, strInfoPlistSHA1, strInfoPlistSHA256);
			}
		}

		if (!archo->Sign(pSignAsset, bForce, strBundleId, strInfoPlistSHA1, strInfoPlistSHA256, strCodeResourcesData))
		{
			if (!archo->m_bEnoughSpace && !m_bCSRealloced)
			{
				m_bCSRealloced = true;
				if (ReallocCodeSignSpace())
				{
					return Sign(pSignAsset, bForce, strBundleId, strInfoPlistSHA1, strInfoPlistSHA256, strCodeResourcesData);
				}
			}
			return false;
		}
	}

	return CloseFile();
}

bool ZMachO::ReallocCodeSignSpace()
{
	ZLog::Warn(">>> Realloc CodeSignature Space... \n");

	vector<uint32_t> arrMachOesSizes;
	for (size_t i = 0; i < m_arrArchOes.size(); i++)
	{
		string strNewArchOFile;
		StringFormat(strNewArchOFile, "%s.archo.%d", m_strFile.c_str(), i);
		uint32_t uNewLength = m_arrArchOes[i]->ReallocCodeSignSpace(strNewArchOFile);
		if (uNewLength <= 0)
		{
			ZLog::Error(">>> Failed!\n");
			return false;
		}
		arrMachOesSizes.push_back(uNewLength);
	}
	ZLog::Warn(">>> Success!\n");

	if (1 == m_arrArchOes.size())
	{
		CloseFile();
		RemoveFile(m_strFile.c_str());
		string strNewArchOFile = m_strFile + ".archo.0";
		if (0 == rename(strNewArchOFile.c_str(), m_strFile.c_str()))
		{
			return OpenFile(m_strFile.c_str());
		}
	}
	else
	{ //fat
		uint32_t uAlign = 16384;
		vector<fat_arch> arrArches;
		fat_header fath = *((fat_header *)m_pBase);
		int nFatArch = (FAT_MAGIC == fath.magic) ? fath.nfat_arch : LE(fath.nfat_arch);
		for (int i = 0; i < nFatArch; i++)
		{
			fat_arch arch = *((fat_arch *)(m_pBase + sizeof(fat_header) + sizeof(fat_arch) * i));
			arrArches.push_back(arch);
		}
		CloseFile();

		if (arrArches.size() != m_arrArchOes.size())
		{
			return false;
		}

		uint32_t uFatHeaderSize = sizeof(fat_header) + arrArches.size() * sizeof(fat_arch);
		uint32_t uPadding1 = (uAlign - uFatHeaderSize % uAlign);
		uint32_t uOffset = uFatHeaderSize + uPadding1;
		for (size_t i = 0; i < arrArches.size(); i++)
		{
			fat_arch &arch = arrArches[i];
			uint32_t &uMachOSize = arrMachOesSizes[i];

			arch.align = (FAT_MAGIC == fath.magic) ? 14 : BE((uint32_t)14);
			arch.offset = (FAT_MAGIC == fath.magic) ? uOffset : BE(uOffset);
			arch.size = (FAT_MAGIC == fath.magic) ? uMachOSize : BE(uMachOSize);

			uOffset += uMachOSize;
			uOffset = uOffset + (uAlign - uOffset % uAlign);
		}

		string strNewFatMachOFile = m_strFile + ".fato";

		string strFatHeader;
		strFatHeader.append((const char *)&fath, sizeof(fat_header));
		for (size_t i = 0; i < arrArches.size(); i++)
		{
			fat_arch &arch = arrArches[i];
			strFatHeader.append((const char *)&arch, sizeof(fat_arch));
		}

		string strPadding1;
		strPadding1.append(uPadding1, 0);

		AppendFile(strNewFatMachOFile.c_str(), strFatHeader);
		AppendFile(strNewFatMachOFile.c_str(), strPadding1);

		for (size_t i = 0; i < arrArches.size(); i++)
		{
			size_t sSize = 0;
			string strNewArchOFile = m_strFile + ".archo." + JValue((int)i).asString();
			uint8_t *pData = (uint8_t *)MapFile(strNewArchOFile.c_str(), 0, 0, &sSize, true);
			if (NULL == pData)
			{
				RemoveFile(strNewFatMachOFile.c_str());
				return false;
			}
			string strPadding;
			strPadding.append((uAlign - sSize % uAlign), 0);

			AppendFile(strNewFatMachOFile.c_str(), (const char *)pData, sSize);
			AppendFile(strNewFatMachOFile.c_str(), strPadding);

			munmap((void *)pData, sSize);
			RemoveFile(strNewArchOFile.c_str());
		}

		RemoveFile(m_strFile.c_str());
		if (0 == rename(strNewFatMachOFile.c_str(), m_strFile.c_str()))
		{
			return OpenFile(m_strFile.c_str());
		}
	}

	return false;
}

bool ZMachO::InjectDyLib(bool bWeakInject, const char *szDyLibPath, bool &bCreate)
{
	ZLog::WarnV(">>> Inject DyLib: %s ... \n", szDyLibPath);

	vector<uint32_t> arrMachOesSizes;
	for (size_t i = 0; i < m_arrArchOes.size(); i++)
	{
		if (!m_arrArchOes[i]->InjectDyLib(bWeakInject, szDyLibPath, bCreate))
		{
			ZLog::Error(">>> Failed!\n");
			return false;
		}
	}
	ZLog::Warn(">>> Success!\n");
	return true;
}

bool ZMachO::ChangeDylibPath(const char *oldPath, const char *newPath) {
	ZLog::WarnV(">>> Change DyLib Path: %s -> %s ... \n", oldPath, newPath);

	bool pathChanged = true;
	for (size_t i = 0; i < m_arrArchOes.size(); i++) {
		if (!m_arrArchOes[i]->ChangeDylibPath(oldPath, newPath)) {
			ZLog::Error(">>> Failed to change path in one of the architectures!\n");
			pathChanged = false;
		}
	}

	if (pathChanged) {
		ZLog::Warn(">>> Successfully changed all dylib paths!\n");
	}
	return pathChanged;
}

std::vector<std::string> ZMachO::ListDylibs() {
	std::vector<std::string> dylibList;

	for (size_t i = 0; i < m_arrArchOes.size(); i++) {
		std::vector<std::string> archDylibs = m_arrArchOes[i]->ListDylibs();
		dylibList.insert(dylibList.end(), archDylibs.begin(), archDylibs.end());
	}

	ZLog::WarnV(">>> Found %zu dylibs:\n", dylibList.size());

	return dylibList;
}
bool ZMachO::RemoveDylib(const std::set<std::string> &dylibNames) {
	ZLog::Warn(">>> Removing specified dylibs...\n");

	bool removalSuccessful = true;
	for (size_t i = 0; i < m_arrArchOes.size(); i++) {
		m_arrArchOes[i]->uninstallDylibs(dylibNames);
	}

	ZLog::Warn(">>> Finished removing specified dylibs!\n");
	return removalSuccessful;
}


bool is_64bit_macho(const char *filepath) {
    FILE *file = fopen(filepath, "rb");
    if (!file) {
        return false; // Failed to open file
    }

    uint32_t magic;
    fread(&magic, sizeof(uint32_t), 1, file);
    fclose(file);

    // check 64-bit Mach-O magic number
    return magic == MH_MAGIC_64 || magic == FAT_CIGAM;
}
