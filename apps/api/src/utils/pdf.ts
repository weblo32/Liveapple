import crypto from 'crypto';

/**
 * Extracts the total page count from a PDF buffer.
 * Inspects /Count in /Pages dictionary or counts /Type /Page objects.
 */
export function extractPdfPageCount(buffer: Buffer): number {
  try {
    const text = buffer.toString('latin1');
    
    // 1. Look for /Type /Pages ... /Count N
    const countMatches = [...text.matchAll(/\/Count\s+(\d+)/g)];
    if (countMatches.length > 0) {
      const counts = countMatches.map((m) => parseInt(m[1], 10)).filter((n) => !isNaN(n) && n > 0);
      if (counts.length > 0) {
        return Math.max(...counts);
      }
    }

    // 2. Fallback: match occurrences of /Type /Page (excluding /Type /Pages)
    const pageMatches = text.match(/\/Type\s*\/Page\b/g);
    if (pageMatches && pageMatches.length > 0) {
      return pageMatches.length;
    }
  } catch (err) {
    console.error('[PDF_UTIL] Error extracting PDF page count:', err);
  }
  return 1;
}

/**
 * Computes SHA-256 hash for a buffer
 */
export function computeSha256(buffer: Buffer): string {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}
