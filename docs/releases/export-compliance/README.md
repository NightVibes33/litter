# Export Compliance: French Encryption Declaration

This folder contains the PDF Apple is asking for:

- `french-encryption-declaration-annex-1.pdf`

Viewer note:

- This is an Adobe XFA form. macOS Preview will show a placeholder page.
- Open it with Adobe Acrobat Reader to view/fill correctly.

## Why this is needed

For this app's current encryption declaration in App Store Connect, France availability is enabled and Apple requires the French declaration approval form before export compliance can be approved.

Current declaration ID:

- `85d5e23f-2cdf-4e9d-a6c6-25e8ae19f40f`

## Fill + upload workflow

1. Open `french-encryption-declaration-annex-1.pdf` and fill it manually (it is not a fillable AcroForm).
2. Print/sign if required by your process.
3. Save the completed file (for example: `french-encryption-declaration-annex-1-completed.pdf`).
4. Upload it to the existing declaration:

```bash
asc encryption documents upload \
  --declaration 85d5e23f-2cdf-4e9d-a6c6-25e8ae19f40f \
  --file docs/releases/export-compliance/french-encryption-declaration-annex-1-completed.pdf
```

5. Check declaration status:

```bash
asc encryption declarations info 85d5e23f-2cdf-4e9d-a6c6-25e8ae19f40f
```

## After upload

In App Store Connect, go to:

- `App Information` -> `App Encryption Documentation`

Wait for the declaration/doc review state to move out of pending, then re-run:

```bash
asc validate com.sigkitten.litter --wait
```

If validation still shows `availability.missing`, set app availability in App Store Connect UI under pricing/availability.
