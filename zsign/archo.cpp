#include "common/common.h"
#include "common/json.h"
#include "archo.h"
#include "signing.h"

static uint64_t execSegLimit = 0;

ZArchO::ZArchO()
{
	m_pBase = NULL;
	m_uLength = 0;
	m_uCodeLength = 0;
	m_pSignBase = NULL;
	m_uSignLength = 0;
	m_pHeader = NULL;
	m_uHeaderSize = 0;
	m_bEncrypted = false;
	m_b64 = false;
	m_bBigEndian = false;
	m_bEnoughSpace = true;
	m_pCodeSignSegment = NULL;
	m_pLinkEditSegment = NULL;
	m_uLoadCommandsFreeSpace = 0;
}

bool ZArchO::Init(uint8_t *pBase, uint32_t uLength)
{
	if (NULL == pBase || uLength <= 0)
	{
		return false;
	}

	m_pBase = pBase;
	m_uLength = uLength;
	m_uCodeLength = (uLength % 16 == 0) ? uLength : uLength + 16 - (uLength % 16);
	m_pHeader = (mach_header *)m_pBase;
	if (MH_MAGIC != m_pHeader->magic && MH_CIGAM != m_pHeader->magic && MH_MAGIC_64 != m_pHeader->magic && MH_CIGAM_64 != m_pHeader->magic)
	{
		return false;
	}

	m_b64 = (MH_MAGIC_64 == m_pHeader->magic || MH_CIGAM_64 == m_pHeader->magic) ? true : false;
	m_bBigEndian = (MH_CIGAM == m_pHeader->magic || MH_CIGAM_64 == m_pHeader->magic) ? true : false;
	m_uHeaderSize = m_b64 ? sizeof(mach_header_64) : sizeof(mach_header);

	uint8_t *pLoadCommand = m_pBase + m_uHeaderSize;
	for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++)
	{
		load_command *plc = (load_command *)pLoadCommand;
		switch (BO(plc->cmd))
		{
		case LC_SEGMENT:
		{
			segment_command *seglc = (segment_command *)pLoadCommand;
			if (0 == strcmp("__TEXT", seglc->segname))
			{
				execSegLimit = seglc->vmsize;
				for (uint32_t j = 0; j < BO(seglc->nsects); j++)
				{
					section *sect = (section *)((pLoadCommand + sizeof(segment_command)) + sizeof(section) * j);
					if (0 == strcmp("__text", sect->sectname))
					{
						if (BO(sect->offset) > (BO(m_pHeader->sizeofcmds) + m_uHeaderSize))
						{
							m_uLoadCommandsFreeSpace = BO(sect->offset) - BO(m_pHeader->sizeofcmds) - m_uHeaderSize;
						}
					}
					else if (0 == strcmp("__info_plist", sect->sectname))
					{
						m_strInfoPlist.append((const char *)m_pBase + BO(sect->offset), BO(sect->size));
					}
				}
			}
			else if (0 == strcmp("__LINKEDIT", seglc->segname))
			{
				m_pLinkEditSegment = pLoadCommand;
			}
		}
		break;
		case LC_SEGMENT_64:
		{
			segment_command_64 *seglc = (segment_command_64 *)pLoadCommand;
			if (0 == strcmp("__TEXT", seglc->segname))
			{
				execSegLimit = seglc->vmsize;
				for (uint32_t j = 0; j < BO(seglc->nsects); j++)
				{
					section_64 *sect = (section_64 *)((pLoadCommand + sizeof(segment_command_64)) + sizeof(section_64) * j);
					if (0 == strcmp("__text", sect->sectname))
					{
						if (BO(sect->offset) > (BO(m_pHeader->sizeofcmds) + m_uHeaderSize))
						{
							m_uLoadCommandsFreeSpace = BO(sect->offset) - BO(m_pHeader->sizeofcmds) - m_uHeaderSize;
						}
					}
					else if (0 == strcmp("__info_plist", sect->sectname))
					{
						m_strInfoPlist.append((const char *)m_pBase + BO(sect->offset), BO((uint32_t)sect->size));
					}
				}
			}
			else if (0 == strcmp("__LINKEDIT", seglc->segname))
			{
				m_pLinkEditSegment = pLoadCommand;
			}
		}
		break;
		case LC_ENCRYPTION_INFO:
		case LC_ENCRYPTION_INFO_64:
		{
			encryption_info_command *crypt_cmd = (encryption_info_command *)pLoadCommand;
			if (BO(crypt_cmd->cryptid) >= 1)
			{
				m_bEncrypted = true;
			}
		}
		break;
		case LC_CODE_SIGNATURE:
		{
			codesignature_command *pcslc = (codesignature_command *)pLoadCommand;
			m_pCodeSignSegment = pLoadCommand;
			m_uCodeLength = BO(pcslc->dataoff);
			m_pSignBase = m_pBase + m_uCodeLength;
			m_uSignLength = GetCodeSignatureLength(m_pSignBase);
		}
		break;
		}

		pLoadCommand += BO(plc->cmdsize);
	}

	return true;
}

const char *ZArchO::GetArch(int cpuType, int cpuSubType)
{
	switch (cpuType)
	{
	case CPU_TYPE_ARM:
	{
		switch (cpuSubType)
		{
		case CPU_SUBTYPE_ARM_V6:
			return "armv6";
			break;
		case CPU_SUBTYPE_ARM_V7:
			return "armv7";
			break;
		case CPU_SUBTYPE_ARM_V7S:
			return "armv7s";
			break;
		case CPU_SUBTYPE_ARM_V7K:
			return "armv7k";
			break;
		case CPU_SUBTYPE_ARM_V8:
			return "armv8";
			break;
		}
	}
	break;
	case CPU_TYPE_ARM64:
	{
		switch (cpuSubType)
		{
		case CPU_SUBTYPE_ARM64_ALL:
			return "arm64";
			break;
		case CPU_SUBTYPE_ARM64_V8:
			return "arm64v8";
			break;
		case 2:
			return "arm64e";
			break;
		}
	}
	break;
	case CPU_TYPE_ARM64_32:
	{
		switch (cpuSubType)
		{
		case CPU_SUBTYPE_ARM64_ALL:
			return "arm64_32";
			break;
		case CPU_SUBTYPE_ARM64_32_V8:
			return "arm64e_32";
			break;
		}
	}
	break;
	case CPU_TYPE_X86:
	{
		switch (cpuSubType)
		{
		default:
			return "x86_32";
			break;
		}
	}
	break;
	case CPU_TYPE_X86_64:
	{
		switch (cpuSubType)
		{
		default:
			return "x86_64";
			break;
		}
	}
	break;
	}
	return "unknown";
}

const char *ZArchO::GetFileType(uint32_t uFileType)
{
	switch (uFileType)
	{
	case MH_OBJECT:
		return "MH_OBJECT";
		break;
	case MH_EXECUTE:
		return "MH_EXECUTE";
		break;
	case MH_FVMLIB:
		return "MH_FVMLIB";
		break;
	case MH_CORE:
		return "MH_CORE";
		break;
	case MH_PRELOAD:
		return "MH_PRELOAD";
		break;
	case MH_DYLIB:
		return "MH_DYLIB";
		break;
	case MH_DYLINKER:
		return "MH_DYLINKER";
		break;
	case MH_BUNDLE:
		return "MH_BUNDLE";
		break;
	case MH_DYLIB_STUB:
		return "MH_DYLIB_STUB";
		break;
	case MH_DSYM:
		return "MH_DSYM";
		break;
	case MH_KEXT_BUNDLE:
		return "MH_KEXT_BUNDLE";
		break;
	}
	return "MH_UNKNOWN";
}

uint32_t ZArchO::BO(uint32_t uValue)
{
	return m_bBigEndian ? LE(uValue) : uValue;
}

bool ZArchO::IsExecute()
{
	if (NULL != m_pHeader)
	{
		return (MH_EXECUTE == BO(m_pHeader->filetype));
	}
	return false;
}

void ZArchO::PrintInfo()
{
	if (NULL == m_pHeader)
	{
		return;
	}

	ZLog::Print("------------------------------------------------------------------\n");
	ZLog::Print(">>> MachO Info: \n");
	ZLog::PrintV("\tFileType: \t%s\n", GetFileType(BO(m_pHeader->filetype)));
	ZLog::PrintV("\tTotalSize: \t%u (%s)\n", m_uLength, FormatSize(m_uLength).c_str());
	ZLog::PrintV("\tPlatform: \t%u\n", m_b64 ? 64 : 32);
	ZLog::PrintV("\tCPUArch: \t%s\n", GetArch(BO(m_pHeader->cputype), BO(m_pHeader->cpusubtype)));
	ZLog::PrintV("\tCPUType: \t0x%x\n", BO(m_pHeader->cputype));
	ZLog::PrintV("\tCPUSubType: \t0x%x\n", BO(m_pHeader->cpusubtype));
	ZLog::PrintV("\tBigEndian: \t%d\n", m_bBigEndian);
	ZLog::PrintV("\tEncrypted: \t%d\n", m_bEncrypted);
	ZLog::PrintV("\tCommandCount: \t%d\n", BO(m_pHeader->ncmds));
	ZLog::PrintV("\tCodeLength: \t%d (%s)\n", m_uCodeLength, FormatSize(m_uCodeLength).c_str());
	ZLog::PrintV("\tSignLength: \t%d (%s)\n", m_uSignLength, FormatSize(m_uSignLength).c_str());
	ZLog::PrintV("\tSpareLength: \t%d (%s)\n", m_uLength - m_uCodeLength - m_uSignLength, FormatSize(m_uLength - m_uCodeLength - m_uSignLength).c_str());

	uint8_t *pLoadCommand = m_pBase + m_uHeaderSize;
	for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++)
	{
		load_command *plc = (load_command *)pLoadCommand;
		if (LC_VERSION_MIN_IPHONEOS == BO(plc->cmd))
		{
			ZLog::PrintV("\tMIN_IPHONEOS: \t0x%x\n", *((uint32_t *)(pLoadCommand + sizeof(load_command))));
		}
		else if (LC_RPATH == BO(plc->cmd))
		{
			ZLog::PrintV("\tLC_RPATH: \t%s\n", (char *)(pLoadCommand + sizeof(load_command) + 4));
		}
		pLoadCommand += BO(plc->cmdsize);
	}

	bool bHasWeakDylib = false;
	ZLog::PrintV("\tLC_LOAD_DYLIB: \n");
	pLoadCommand = m_pBase + m_uHeaderSize;
	for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++)
	{
		load_command *plc = (load_command *)pLoadCommand;
		if (LC_LOAD_DYLIB == BO(plc->cmd))
		{
			dylib_command *dlc = (dylib_command *)pLoadCommand;
			const char *szDyLib = (const char *)(pLoadCommand + BO(dlc->dylib.name.offset));
			ZLog::PrintV("\t\t\t%s\n", szDyLib);
		}
		else if (LC_LOAD_WEAK_DYLIB == BO(plc->cmd))
		{
			bHasWeakDylib = true;
		}
		pLoadCommand += BO(plc->cmdsize);
	}

	if (bHasWeakDylib)
	{
		ZLog::PrintV("\tLC_LOAD_WEAK_DYLIB: \n");
		pLoadCommand = m_pBase + m_uHeaderSize;
		for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++)
		{
			load_command *plc = (load_command *)pLoadCommand;
			if (LC_LOAD_WEAK_DYLIB == BO(plc->cmd))
			{
				dylib_command *dlc = (dylib_command *)pLoadCommand;
				const char *szDyLib = (const char *)(pLoadCommand + BO(dlc->dylib.name.offset));
				ZLog::PrintV("\t\t\t%s (weak)\n", szDyLib);
			}
			pLoadCommand += BO(plc->cmdsize);
		}
	}

	if (!m_strInfoPlist.empty())
	{
		ZLog::Print("\n>>> Embedded Info.plist: \n");
		ZLog::PrintV("\tlength: \t%lu\n", m_strInfoPlist.size());

		string strInfoPlist = m_strInfoPlist;
		PWriter::StringReplace(strInfoPlist, "\n", "\n\t\t\t");
		ZLog::PrintV("\tcontent: \t%s\n", strInfoPlist.c_str());

		PrintDataSHASum("\tSHA-1:  \t", E_SHASUM_TYPE_1, m_strInfoPlist);
		PrintDataSHASum("\tSHA-256:\t", E_SHASUM_TYPE_256, m_strInfoPlist);
	}

	if (NULL == m_pSignBase || m_uSignLength <= 0)
	{
		ZLog::Warn(">>> Can't Find CodeSignature Segment!\n");
	}
	else
	{
		ParseCodeSignature(m_pSignBase);
	}

	ZLog::Print("------------------------------------------------------------------\n");
}

bool ZArchO::BuildCodeSignature(ZSignAsset *pSignAsset, bool bForce, const string &strBundleId, const string &strInfoPlistSHA1, const string &strInfoPlistSHA256, const string &strCodeResourcesSHA1, const string &strCodeResourcesSHA256, string &strOutput)
{
	string strRequirementsSlot;
	string strEntitlementsSlot;
	string strDerEntitlementsSlot;

    // modified, we don't need Entitlement in LiveContainer.
//	string strEmptyEntitlements = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict/>\n</plist>\n";
    string strEmptyEntitlements = "";
	SlotBuildRequirements(strBundleId, pSignAsset->m_strSubjectCN, strRequirementsSlot);
	SlotBuildEntitlements(IsExecute() ? pSignAsset->m_strEntitlementsData : strEmptyEntitlements, strEntitlementsSlot);
	SlotBuildDerEntitlements(IsExecute() ? pSignAsset->m_strEntitlementsData : "", strDerEntitlementsSlot);

	string strRequirementsSlotSHA1;
	string strRequirementsSlotSHA256;
	if (strRequirementsSlot.empty())
	{ //empty
		strRequirementsSlotSHA1.append(20, 0);
		strRequirementsSlotSHA256.append(32, 0);
	}
	else
	{
		SHASum(strRequirementsSlot, strRequirementsSlotSHA1, strRequirementsSlotSHA256);
	}

	string strEntitlementsSlotSHA1;
	string strEntitlementsSlotSHA256;
	if (strEntitlementsSlot.empty())
	{ //empty
		strEntitlementsSlotSHA1.append(20, 0);
		strEntitlementsSlotSHA256.append(32, 0);
	}
	else
	{
		SHASum(strEntitlementsSlot, strEntitlementsSlotSHA1, strEntitlementsSlotSHA256);
	}

	string strDerEntitlementsSlotSHA1;
	string strDerEntitlementsSlotSHA256;
	if (strDerEntitlementsSlot.empty())
	{ //empty
		strDerEntitlementsSlotSHA1.append(20, 0);
		strDerEntitlementsSlotSHA256.append(32, 0);
	}
	else
	{
		SHASum(strDerEntitlementsSlot, strDerEntitlementsSlotSHA1, strDerEntitlementsSlotSHA256);
	}

	uint8_t *pCodeSlots1Data = NULL;
	uint8_t *pCodeSlots256Data = NULL;
	uint32_t uCodeSlots1DataLength = 0;
	uint32_t uCodeSlots256DataLength = 0;
	if (!bForce)
	{
		GetCodeSignatureExistsCodeSlotsData(m_pSignBase, pCodeSlots1Data, uCodeSlots1DataLength, pCodeSlots256Data, uCodeSlots256DataLength);
	}

	uint64_t execSegFlags = 0;
	if (NULL != strstr(strEntitlementsSlot.data() + 8, "<key>get-task-allow</key>"))
	{
		// TODO: Check if get-task-allow is actually set to true
		execSegFlags = CS_EXECSEG_MAIN_BINARY | CS_EXECSEG_ALLOW_UNSIGNED;
	}

	string strCMSSignatureSlot;
	string strCodeDirectorySlot;
	string strAltnateCodeDirectorySlot;
	SlotBuildCodeDirectory(false,
						   m_pBase,
						   m_uCodeLength,
						   pCodeSlots1Data,
						   uCodeSlots1DataLength,
						   execSegLimit,
						   execSegFlags,
						   strBundleId,
						   pSignAsset->m_strTeamId,
						   strInfoPlistSHA1,
						   strRequirementsSlotSHA1,
						   strCodeResourcesSHA1,
						   strEntitlementsSlotSHA1,
						   strDerEntitlementsSlotSHA1,
						   IsExecute(),
						   strCodeDirectorySlot);
	SlotBuildCodeDirectory(true,
						   m_pBase,
						   m_uCodeLength,
						   pCodeSlots256Data,
						   uCodeSlots256DataLength,
						   execSegLimit,
						   execSegFlags,
						   strBundleId,
						   pSignAsset->m_strTeamId,
						   strInfoPlistSHA256,
						   strRequirementsSlotSHA256,
						   strCodeResourcesSHA256,
						   strEntitlementsSlotSHA256,
						   strDerEntitlementsSlotSHA256,
						   IsExecute(),
						   strAltnateCodeDirectorySlot);
	SlotBuildCMSSignature(pSignAsset,
						  strCodeDirectorySlot,
						  strAltnateCodeDirectorySlot,
						  strCMSSignatureSlot);

	uint32_t uCodeDirectorySlotLength = (uint32_t)strCodeDirectorySlot.size();
	uint32_t uRequirementsSlotLength = (uint32_t)strRequirementsSlot.size();
	uint32_t uEntitlementsSlotLength = (uint32_t)strEntitlementsSlot.size();
	uint32_t uDerEntitlementsLength = (uint32_t)strDerEntitlementsSlot.size();
	uint32_t uAltnateCodeDirectorySlotLength = (uint32_t)strAltnateCodeDirectorySlot.size();
	uint32_t uCMSSignatureSlotLength = (uint32_t)strCMSSignatureSlot.size();

	uint32_t uCodeSignBlobCount = 0;
	uCodeSignBlobCount += (uCodeDirectorySlotLength > 0) ? 1 : 0;
	uCodeSignBlobCount += (uRequirementsSlotLength > 0) ? 1 : 0;
	uCodeSignBlobCount += (uEntitlementsSlotLength > 0) ? 1 : 0;
	uCodeSignBlobCount += (uDerEntitlementsLength > 0) ? 1 : 0;
	uCodeSignBlobCount += (uAltnateCodeDirectorySlotLength > 0) ? 1 : 0;
	uCodeSignBlobCount += (uCMSSignatureSlotLength > 0) ? 1 : 0;

	uint32_t uSuperBlobHeaderLength = sizeof(CS_SuperBlob) + uCodeSignBlobCount * sizeof(CS_BlobIndex);
	uint32_t uCodeSignLength = uSuperBlobHeaderLength +
							   uCodeDirectorySlotLength +
							   uRequirementsSlotLength +
							   uEntitlementsSlotLength +
							   uDerEntitlementsLength +
							   uAltnateCodeDirectorySlotLength +
							   uCMSSignatureSlotLength;

	vector<CS_BlobIndex> arrBlobIndexes;
	if (uCodeDirectorySlotLength > 0)
	{
		CS_BlobIndex blob;
		blob.type = BE(CSSLOT_CODEDIRECTORY);
		blob.offset = BE(uSuperBlobHeaderLength);
		arrBlobIndexes.push_back(blob);
	}
	if (uRequirementsSlotLength > 0)
	{
		CS_BlobIndex blob;
		blob.type = BE(CSSLOT_REQUIREMENTS);
		blob.offset = BE(uSuperBlobHeaderLength + uCodeDirectorySlotLength);
		arrBlobIndexes.push_back(blob);
	}
	if (uEntitlementsSlotLength > 0)
	{
		CS_BlobIndex blob;
		blob.type = BE(CSSLOT_ENTITLEMENTS);
		blob.offset = BE(uSuperBlobHeaderLength + uCodeDirectorySlotLength + uRequirementsSlotLength);
		arrBlobIndexes.push_back(blob);
	}
	if (uDerEntitlementsLength > 0)
	{
		CS_BlobIndex blob;
		blob.type = BE(CSSLOT_DER_ENTITLEMENTS);
		blob.offset = BE(uSuperBlobHeaderLength + uCodeDirectorySlotLength + uRequirementsSlotLength + uEntitlementsSlotLength);
		arrBlobIndexes.push_back(blob);
	}
	if (uAltnateCodeDirectorySlotLength > 0)
	{
		CS_BlobIndex blob;
		blob.type = BE(CSSLOT_ALTERNATE_CODEDIRECTORIES);
		blob.offset = BE(uSuperBlobHeaderLength + uCodeDirectorySlotLength + uRequirementsSlotLength + uEntitlementsSlotLength + uDerEntitlementsLength);
		arrBlobIndexes.push_back(blob);
	}
	if (uCMSSignatureSlotLength > 0)
	{
		CS_BlobIndex blob;
		blob.type = BE(CSSLOT_SIGNATURESLOT);
		blob.offset = BE(uSuperBlobHeaderLength + uCodeDirectorySlotLength + uRequirementsSlotLength + uEntitlementsSlotLength + uDerEntitlementsLength + uAltnateCodeDirectorySlotLength);
		arrBlobIndexes.push_back(blob);
	}

	CS_SuperBlob superblob;
	superblob.magic = BE(CSMAGIC_EMBEDDED_SIGNATURE);
	superblob.length = BE(uCodeSignLength);
	superblob.count = BE(uCodeSignBlobCount);

	strOutput.clear();
	strOutput.reserve(uCodeSignLength);
	strOutput.append((const char *)&superblob, sizeof(superblob));
	for (size_t i = 0; i < arrBlobIndexes.size(); i++)
	{
		CS_BlobIndex &blob = arrBlobIndexes[i];
		strOutput.append((const char *)&blob, sizeof(blob));
	}
	strOutput += strCodeDirectorySlot;
	strOutput += strRequirementsSlot;
	strOutput += strEntitlementsSlot;
	strOutput += strDerEntitlementsSlot;
	strOutput += strAltnateCodeDirectorySlot;
	strOutput += strCMSSignatureSlot;

	if (ZLog::IsDebug())
	{
		WriteFile("./.zsign_debug/Requirements.slot.new", strRequirementsSlot);
		WriteFile("./.zsign_debug/Entitlements.slot.new", strEntitlementsSlot);
		WriteFile("./.zsign_debug/Entitlements.der.slot.new", strDerEntitlementsSlot);
		WriteFile("./.zsign_debug/Entitlements.plist.new", strEntitlementsSlot.data() + 8, strEntitlementsSlot.size() - 8);
		WriteFile("./.zsign_debug/CodeDirectory_SHA1.slot.new", strCodeDirectorySlot);
		WriteFile("./.zsign_debug/CodeDirectory_SHA256.slot.new", strAltnateCodeDirectorySlot);
		WriteFile("./.zsign_debug/CMSSignature.slot.new", strCMSSignatureSlot);
		WriteFile("./.zsign_debug/CMSSignature.der.new", strCMSSignatureSlot.data() + 8, strCMSSignatureSlot.size() - 8);
		WriteFile("./.zsign_debug/CodeSignature.blob.new", strOutput);
	}

	return true;
}

bool ZArchO::Sign(ZSignAsset *pSignAsset, bool bForce, const string &strBundleId, const string &strInfoPlistSHA1, const string &strInfoPlistSHA256, const string &strCodeResourcesData)
{
	if (NULL == m_pSignBase)
	{
		m_bEnoughSpace = false;
		ZLog::Warn(">>> Can't Find CodeSignature Segment!\n");
		return false;
	}

	string strCodeResourcesSHA1;
	string strCodeResourcesSHA256;
	if (strCodeResourcesData.empty())
	{
		strCodeResourcesSHA1.append(20, 0);
		strCodeResourcesSHA256.append(32, 0);
	}
	else
	{
		SHASum(strCodeResourcesData, strCodeResourcesSHA1, strCodeResourcesSHA256);
	}

	string strCodeSignBlob;
	BuildCodeSignature(pSignAsset, bForce, strBundleId, strInfoPlistSHA1, strInfoPlistSHA256, strCodeResourcesSHA1, strCodeResourcesSHA256, strCodeSignBlob);
	if (strCodeSignBlob.empty())
	{
		ZLog::Error(">>> Build CodeSignature Failed!\n");
		return false;
	}

	int nSpaceLength = (int)m_uLength - (int)m_uCodeLength - (int)strCodeSignBlob.size();
	if (nSpaceLength < 0)
	{
		m_bEnoughSpace = false;
		ZLog::WarnV(">>> No Enough CodeSignature Space. Length => Now: %d, Need: %d\n", (int)m_uLength - (int)m_uCodeLength, (int)strCodeSignBlob.size());
		return false;
	}

	memcpy(m_pBase + m_uCodeLength, strCodeSignBlob.data(), strCodeSignBlob.size());
	//memset(m_pBase + m_uCodeLength + strCodeSignBlob.size(), 0, nSpaceLength);
	return true;
}

uint32_t ZArchO::ReallocCodeSignSpace(const string &strNewFile)
{
	RemoveFile(strNewFile.c_str());

	uint32_t uNewLength = m_uCodeLength + ByteAlign(((m_uCodeLength / 4096) + 1) * (20 + 32), 4096) + 16384; //16K May Be Enough
	if (NULL == m_pLinkEditSegment || uNewLength <= m_uLength)
	{
		return 0;
	}

	load_command *pseglc = (load_command *)m_pLinkEditSegment;
	switch (BO(pseglc->cmd))
	{
	case LC_SEGMENT:
	{
		segment_command *seglc = (segment_command *)m_pLinkEditSegment;
		seglc->vmsize = ByteAlign(BO(seglc->vmsize) + (uNewLength - m_uLength), 4096);
		seglc->vmsize = BO(seglc->vmsize);
		seglc->filesize = uNewLength - BO(seglc->fileoff);
		seglc->filesize = BO(seglc->filesize);
	}
	break;
	case LC_SEGMENT_64:
	{
		segment_command_64 *seglc = (segment_command_64 *)m_pLinkEditSegment;
		seglc->vmsize = ByteAlign(BO((uint32_t)seglc->vmsize) + (uNewLength - m_uLength), 4096);
		seglc->vmsize = BO((uint32_t)seglc->vmsize);
		seglc->filesize = uNewLength - BO((uint32_t)seglc->fileoff);
		seglc->filesize = BO((uint32_t)seglc->filesize);
	}
	break;
	}

	codesignature_command *pcslc = (codesignature_command *)m_pCodeSignSegment;
	if (NULL == pcslc)
	{
		if (m_uLoadCommandsFreeSpace < 4)
		{
			ZLog::Error(">>> Can't Find Free Space Of LoadCommands For CodeSignature!\n");
			return 0;
		}

		pcslc = (codesignature_command *)(m_pBase + m_uHeaderSize + BO(m_pHeader->sizeofcmds));
		pcslc->cmd = BO(LC_CODE_SIGNATURE);
		pcslc->cmdsize = BO((uint32_t)sizeof(codesignature_command));
		pcslc->dataoff = BO(m_uCodeLength);
		m_pHeader->ncmds = BO(BO(m_pHeader->ncmds) + 1);
		m_pHeader->sizeofcmds = BO(BO(m_pHeader->sizeofcmds) + sizeof(codesignature_command));
	}
	pcslc->datasize = BO(uNewLength - m_uCodeLength);

	if (!AppendFile(strNewFile.c_str(), (const char *)m_pBase, m_uLength))
	{
		return 0;
	}

	string strPadding;
	strPadding.append(uNewLength - m_uLength, 0);
	if (!AppendFile(strNewFile.c_str(), strPadding))
	{
		RemoveFile(strNewFile.c_str());
		return 0;
	}

	return uNewLength;
}

bool ZArchO::InjectDyLib(bool bWeakInject, const char *szDyLibPath, bool &bCreate)
{
	if (NULL == m_pHeader)
	{
		return false;
	}

	uint8_t *pLoadCommand = m_pBase + m_uHeaderSize;
	for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++)
	{
		load_command *plc = (load_command *)pLoadCommand;
		uint32_t uLoadType = BO(plc->cmd);
		if (LC_LOAD_DYLIB == uLoadType || LC_LOAD_WEAK_DYLIB == uLoadType)
		{
			dylib_command *dlc = (dylib_command *)pLoadCommand;
			const char *szDyLib = (const char *)(pLoadCommand + BO(dlc->dylib.name.offset));
			if (0 == strcmp(szDyLib, szDyLibPath))
			{
				if ((bWeakInject && (LC_LOAD_WEAK_DYLIB != uLoadType)) || (!bWeakInject && (LC_LOAD_DYLIB != uLoadType)))
				{
					dlc->cmd = BO((uint32_t)(bWeakInject ? LC_LOAD_WEAK_DYLIB : LC_LOAD_DYLIB));
					ZLog::WarnV(">>> DyLib Load Type Changed! %s -> %s\n", (LC_LOAD_DYLIB == uLoadType) ? "LC_LOAD_DYLIB" : "LC_LOAD_WEAK_DYLIB", bWeakInject ? "LC_LOAD_WEAK_DYLIB" : "LC_LOAD_DYLIB");
				}
				else
				{
					ZLog::WarnV(">>> DyLib Is Already Existed! %s\n");
				}
				return true;
			}
		}
		pLoadCommand += BO(plc->cmdsize);
	}

	uint32_t uDylibPathLength = (uint32_t)strlen(szDyLibPath);
	uint32_t uDylibPathPadding = (8 - uDylibPathLength % 8);
	uint32_t uDyLibCommandSize = sizeof(dylib_command) + uDylibPathLength + uDylibPathPadding;
	if (m_uLoadCommandsFreeSpace > 0 && m_uLoadCommandsFreeSpace < uDyLibCommandSize) // some bin doesn't have '__text'
	{
		ZLog::Error(">>> Can't Find Free Space Of LoadCommands For LC_LOAD_DYLIB Or LC_LOAD_WEAK_DYLIB!\n");
		return false;
	}

	//add
	dylib_command *dlc = (dylib_command *)(m_pBase + m_uHeaderSize + BO(m_pHeader->sizeofcmds));
	dlc->cmd = BO((uint32_t)(bWeakInject ? LC_LOAD_WEAK_DYLIB : LC_LOAD_DYLIB));
	dlc->cmdsize = BO(uDyLibCommandSize);
	dlc->dylib.name.offset = BO((uint32_t)sizeof(dylib_command));
	dlc->dylib.timestamp = BO((uint32_t)2);
	dlc->dylib.current_version = 0;
	dlc->dylib.compatibility_version = 0;

	string strDylibPath = szDyLibPath;
	strDylibPath.append(uDylibPathPadding, 0);

	uint8_t *pDyLibPath = (uint8_t *)dlc + sizeof(dylib_command);
	memcpy(pDyLibPath, strDylibPath.data(), uDylibPathLength + uDylibPathPadding);

	m_pHeader->ncmds = BO(BO(m_pHeader->ncmds) + 1);
	m_pHeader->sizeofcmds = BO(BO(m_pHeader->sizeofcmds) + uDyLibCommandSize);

	bCreate = true;
	return true;
}

bool ZArchO::ChangeDylibPath(const char *oldPath, const char *newPath) {
	if (NULL == m_pHeader) {
		return false;
	}

	uint8_t *pLoadCommand = m_pBase + m_uHeaderSize;
	bool pathChanged = false;
	uint32_t oldPathLength = (uint32_t)strlen(oldPath);
	uint32_t newPathLength = (uint32_t)strlen(newPath);
	uint32_t oldPathPadding = (8 - oldPathLength % 8) % 8;
	uint32_t newPathPadding = (8 - newPathLength % 8) % 8;
	uint32_t newLoadCommandSize = 0;

	for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++) {
		load_command *plc = (load_command *)pLoadCommand;
		uint32_t uLoadType = BO(plc->cmd);

		if (LC_LOAD_DYLIB == uLoadType || LC_LOAD_WEAK_DYLIB == uLoadType) {
			dylib_command *dlc = (dylib_command *)pLoadCommand;
			const char *szDyLib = (const char *)(pLoadCommand + BO(dlc->dylib.name.offset));

			if (strcmp(szDyLib, oldPath) == 0) {
				uint32_t dylibPathOffset = sizeof(dylib_command);
				uint32_t dylibPathSize = newPathLength + newPathPadding;
				if (dylibPathOffset + dylibPathSize > BO(plc->cmdsize)) {
					ZLog::Error(">>> Insufficient space to update dylib path!\n");
					return false;
				}

				memcpy(pLoadCommand + dylibPathOffset, newPath, newPathLength);
				memset(pLoadCommand + dylibPathOffset + newPathLength, 0, newPathPadding);

				ZLog::PrintV(">>> Dylib Path Changed: %s -> %s\n", oldPath, newPath);

				pathChanged = true;
			}
		}

		pLoadCommand += BO(plc->cmdsize);
	}

	if (!pathChanged) {
		ZLog::PrintV(">>> Old Dylib Path Not Found: %s\n", oldPath);
	}

	return pathChanged;
}






void ZArchO::uninstallDylibs(set<string> dylibNames)
{
    uint8_t *pLoadCommand = m_pBase + m_uHeaderSize;
    uint32_t old_load_command_size = m_pHeader->sizeofcmds;
    uint8_t *new_load_command_data = (uint8_t*)malloc(old_load_command_size);
    memset(new_load_command_data,0,old_load_command_size);
    uint32_t new_load_command_size = 0;
    uint32_t clear_num = 0;
    uint32_t clear_data_size = 0;
    for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++)
    {
        load_command *plc = (load_command *)pLoadCommand;
        uint32_t load_command_size = BO(plc->cmdsize);
        if (LC_LOAD_DYLIB == BO(plc->cmd) || LC_LOAD_WEAK_DYLIB == BO(plc->cmd))
        {
            dylib_command *dlc = (dylib_command *)pLoadCommand;
            const char *szDyLib = (const char *)(pLoadCommand + BO(dlc->dylib.name.offset));
            string dylibName = szDyLib;
            if(dylibNames.count(dylibName)>0){
                ZLog::PrintV("\t\t\t%s\tclear\n", szDyLib);
                clear_num++;
                clear_data_size+=load_command_size;
                pLoadCommand += BO(plc->cmdsize);
                continue;
            }
            ZLog::PrintV("\t\t\t%s\n", szDyLib);
        }
        new_load_command_size+=load_command_size;
        memcpy(new_load_command_data,pLoadCommand,load_command_size);
        new_load_command_data += load_command_size;
        pLoadCommand += BO(plc->cmdsize);
    }
    pLoadCommand -= m_pHeader->sizeofcmds;

    m_pHeader->ncmds -= clear_num;
    m_pHeader->sizeofcmds -= clear_data_size;
    new_load_command_data -=new_load_command_size;
    memset(pLoadCommand,0,old_load_command_size);
    memcpy(pLoadCommand,new_load_command_data,new_load_command_size);
    free(new_load_command_data);
}

std::vector<std::string> ZArchO::ListDylibs() {
	std::vector<std::string> dylibList;
	uint8_t *pLoadCommand = m_pBase + m_uHeaderSize;

	for (uint32_t i = 0; i < BO(m_pHeader->ncmds); i++) {
		load_command *plc = (load_command *)pLoadCommand;
		if (LC_LOAD_DYLIB == BO(plc->cmd) || LC_LOAD_WEAK_DYLIB == BO(plc->cmd)) {
			dylib_command *dlc = (dylib_command *)pLoadCommand;
			const char *szDyLib = (const char *)(pLoadCommand + BO(dlc->dylib.name.offset));
			dylibList.push_back(std::string(szDyLib));
		}
		pLoadCommand += BO(plc->cmdsize);
	}

	return dylibList;
}

