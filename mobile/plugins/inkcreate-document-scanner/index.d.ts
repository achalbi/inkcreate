export type DocumentScannerFormat = "jpeg" | "pdf";

export type DocumentScannerMode = "base" | "base-with-filter" | "full";

export interface DocumentScannerScanOptions {
  formats?: DocumentScannerFormat[];
  pageLimit?: number;
  allowGalleryImport?: boolean;
  scannerMode?: DocumentScannerMode;
  title?: string;
}

export interface DocumentScannerPageResult {
  imageDataUrl?: string;
  pageIndex?: number;
}

export interface DocumentScannerScanResult {
  cancelled?: boolean;
  title?: string;
  previewImageDataUrl?: string;
  pdfDataUrl?: string;
  pageCount?: number;
  pages?: DocumentScannerPageResult[];
}

export interface InkcreateDocumentScannerPlugin {
  scanDocument(options?: DocumentScannerScanOptions): Promise<DocumentScannerScanResult>;
  startScan(options?: DocumentScannerScanOptions): Promise<DocumentScannerScanResult>;
  openScanner(options?: DocumentScannerScanOptions): Promise<DocumentScannerScanResult>;
}

export const InkcreateDocumentScanner: InkcreateDocumentScannerPlugin;

export default InkcreateDocumentScanner;
