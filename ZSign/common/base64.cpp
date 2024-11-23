#include "base64.h"
#include <string.h>

#define B0(a) (a & 0xFF)
#define B1(a) (a >> 8 & 0xFF)
#define B2(a) (a >> 16 & 0xFF)
#define B3(a) (a >> 24 & 0xFF)

ZBase64::ZBase64(void)
{
}

ZBase64::~ZBase64(void)
{
	if (!m_arrEnc.empty())
	{
		for (size_t i = 0; i < m_arrEnc.size(); i++)
		{
			delete[] m_arrEnc[i];
		}
		m_arrEnc.clear();
	}

	if (!m_arrDec.empty())
	{
		for (size_t i = 0; i < m_arrDec.size(); i++)
		{
			delete[] m_arrDec[i];
		}
		m_arrDec.clear();
	}
}

char ZBase64::GetB64char(int nIndex)
{
	static const char szTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	if (nIndex >= 0 && nIndex < 64)
	{
		return szTable[nIndex];
	}
	return '=';
}

int ZBase64::GetB64Index(char ch)
{
	int index = -1;
	if (ch >= 'A' && ch <= 'Z')
	{
		index = ch - 'A';
	}
	else if (ch >= 'a' && ch <= 'z')
	{
		index = ch - 'a' + 26;
	}
	else if (ch >= '0' && ch <= '9')
	{
		index = ch - '0' + 52;
	}
	else if (ch == '+')
	{
		index = 62;
	}
	else if (ch == '/')
	{
		index = 63;
	}
	return index;
}

const char *ZBase64::Encode(const char *szSrc, int nSrcLen)
{
	if (0 == nSrcLen)
	{
		nSrcLen = (int)strlen(szSrc);
	}

	if (nSrcLen <= 0)
	{
		return "";
	}

	char *szEnc = new char[nSrcLen * 3 + 128];
	m_arrEnc.push_back(szEnc);

	int i = 0;
	int len = 0;
	unsigned char *psrc = (unsigned char *)szSrc;
	char *p64 = szEnc;
	for (i = 0; i < nSrcLen - 3; i += 3)
	{
		unsigned long ulTmp = *(unsigned long *)psrc;
		int b0 = GetB64char((B0(ulTmp) >> 2) & 0x3F);
		int b1 = GetB64char((B0(ulTmp) << 6 >> 2 | B1(ulTmp) >> 4) & 0x3F);
		int b2 = GetB64char((B1(ulTmp) << 4 >> 2 | B2(ulTmp) >> 6) & 0x3F);
		int b3 = GetB64char((B2(ulTmp) << 2 >> 2) & 0x3F);
		*((unsigned long *)p64) = b0 | b1 << 8 | b2 << 16 | b3 << 24;
		len += 4;
		p64 += 4;
		psrc += 3;
	}

	if (i < nSrcLen)
	{
		int rest = nSrcLen - i;
		unsigned long ulTmp = 0;
		for (int j = 0; j < rest; ++j)
		{
			*(((unsigned char *)&ulTmp) + j) = *psrc++;
		}
		p64[0] = GetB64char((B0(ulTmp) >> 2) & 0x3F);
		p64[1] = GetB64char((B0(ulTmp) << 6 >> 2 | B1(ulTmp) >> 4) & 0x3F);
		p64[2] = rest > 1 ? GetB64char((B1(ulTmp) << 4 >> 2 | B2(ulTmp) >> 6) & 0x3F) : '=';
		p64[3] = rest > 2 ? GetB64char((B2(ulTmp) << 2 >> 2) & 0x3F) : '=';
		p64 += 4;
		len += 4;
	}
	*p64 = '\0';
	return szEnc;
}

const char *ZBase64::Encode(const string &strInput)
{
	return Encode(strInput.data(), strInput.size());
}

const char *ZBase64::Decode(const char *szSrc, int nSrcLen, int *pDecLen)
{
	if (0 == nSrcLen)
	{
		nSrcLen = (int)strlen(szSrc);
	}

	if (nSrcLen <= 0)
	{
		return "";
	}

	char *szDec = new char[nSrcLen];
	m_arrDec.push_back(szDec);

	int i = 0;
	int len = 0;
	unsigned char *psrc = (unsigned char *)szSrc;
	char *pbuf = szDec;
	for (i = 0; i < nSrcLen - 4; i += 4)
	{
		unsigned long ulTmp = *(unsigned long *)psrc;

		int b0 = (GetB64Index((char)B0(ulTmp)) << 2 | GetB64Index((char)B1(ulTmp)) << 2 >> 6) & 0xFF;
		int b1 = (GetB64Index((char)B1(ulTmp)) << 4 | GetB64Index((char)B2(ulTmp)) << 2 >> 4) & 0xFF;
		int b2 = (GetB64Index((char)B2(ulTmp)) << 6 | GetB64Index((char)B3(ulTmp)) << 2 >> 2) & 0xFF;

		*((unsigned long *)pbuf) = b0 | b1 << 8 | b2 << 16;
		psrc += 4;
		pbuf += 3;
		len += 3;
	}

	if (i < nSrcLen)
	{
		int rest = nSrcLen - i;
		unsigned long ulTmp = 0;
		for (int j = 0; j < rest; ++j)
		{
			*(((unsigned char *)&ulTmp) + j) = *psrc++;
		}

		int b0 = (GetB64Index((char)B0(ulTmp)) << 2 | GetB64Index((char)B1(ulTmp)) << 2 >> 6) & 0xFF;
		*pbuf++ = b0;
		len++;

		if ('=' != B1(ulTmp) && '=' != B2(ulTmp))
		{
			int b1 = (GetB64Index((char)B1(ulTmp)) << 4 | GetB64Index((char)B2(ulTmp)) << 2 >> 4) & 0xFF;
			*pbuf++ = b1;
			len++;
		}

		if ('=' != B2(ulTmp) && '=' != B3(ulTmp))
		{
			int b2 = (GetB64Index((char)B2(ulTmp)) << 6 | GetB64Index((char)B3(ulTmp)) << 2 >> 2) & 0xFF;
			*pbuf++ = b2;
			len++;
		}
	}
	*pbuf = '\0';

	if (NULL != pDecLen)
	{
		*pDecLen = (int)(pbuf - szDec);
	}

	return szDec;
}

const char *ZBase64::Decode(const char *szSrc, string &strOutput)
{
	strOutput.clear();
	int nDecLen = 0;
	const char *p = Decode(szSrc, 0, &nDecLen);
	strOutput.append(p, nDecLen);
	return strOutput.data();
}
