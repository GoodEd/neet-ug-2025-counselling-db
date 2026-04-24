create schema if not exists neetcounselling2025;

create table if not exists neetcounselling2025.tabula_extracted_rows (
  id bigserial primary key,
  source_pdf text not null,
  source_pdf_path text not null,
  source_pdf_sha256 text not null,
  table_index int not null,
  extracted_at timestamptz not null default now(),
  row_data jsonb not null
);

create index if not exists idx_tabula_extracted_rows_pdf
  on neetcounselling2025.tabula_extracted_rows (source_pdf);

create index if not exists idx_tabula_extracted_rows_sha
  on neetcounselling2025.tabula_extracted_rows (source_pdf_sha256);

create table if not exists neetcounselling2025.tabula_ingestion_windows (
  source_pdf text not null,
  source_pdf_sha256 text not null,
  page_start int not null,
  page_end int not null,
  completed_at timestamptz not null default now(),
  primary key (source_pdf_sha256, page_start, page_end)
);

create index if not exists idx_tabula_ingestion_windows_pdf
  on neetcounselling2025.tabula_ingestion_windows (source_pdf);
