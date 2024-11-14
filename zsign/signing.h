#pragma once
#include "openssl.h"

bool ParseCodeSignature(uint8_t *pCSBase);
bool SlotBuildEntitlements(const string &strEntitlements, string &strOutput);
bool SlotBuildDerEntitlements(const string &strEntitlements, string &strOutput);
bool SlotBuildRequirements(const string &strBundleID, const string &strSubjectCN, string &strOutput);
bool GetCodeSignatureCodeSlotsData(uint8_t *pCSBase, uint8_t *&pCodeSlots1, uint32_t &uCodeSlots1Length, uint8_t *&pCodeSlots256, uint32_t &uCodeSlots256Length);
bool SlotBuildCodeDirectory(bool bAlternate,
							uint8_t *pCodeBase,
							uint32_t uCodeLength,
							uint8_t *pCodeSlotsData,
							uint32_t uCodeSlotsDataLength,
							uint64_t execSegLimit,
							uint64_t execSegFlags,
							const string &strBundleId,
							const string &strTeamId,
							const string &strInfoPlistSHA,
							const string &strRequirementsSlotSHA,
							const string &strCodeResourcesSHA,
							const string &strEntitlementsSlotSHA,
							const string &strDerEntitlementsSlotSHA,
							bool isExecuteArch,
							string &strOutput);
bool SlotBuildCMSSignature(ZSignAsset *pSignAsset,
						   const string &strCodeDirectorySlot,
						   const string &strAltnateCodeDirectorySlot,
						   string &strOutput);
bool GetCodeSignatureExistsCodeSlotsData(uint8_t *pCSBase,
										 uint8_t *&pCodeSlots1Data,
										 uint32_t &uCodeSlots1DataLength,
										 uint8_t *&pCodeSlots256Data,
										 uint32_t &uCodeSlots256DataLength);
uint32_t GetCodeSignatureLength(uint8_t *pCSBase);
