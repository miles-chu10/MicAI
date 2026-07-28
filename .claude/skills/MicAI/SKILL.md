```markdown
# MicAI Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches you the core development patterns and conventions used in the MicAI TypeScript codebase. You'll learn the project's preferred file naming, import/export styles, commit message conventions, and how to write and organize tests. This guide also provides suggested commands for common workflows.

## Coding Conventions

### File Naming
- Use **PascalCase** for all file names.
  - Example: `UserProfile.ts`, `DataFetcher.test.ts`

### Import Style
- Use **relative imports** for referencing modules within the project.
  - Example:
    ```typescript
    import { fetchData } from './DataFetcher';
    ```

### Export Style
- Use **named exports** for all modules.
  - Example:
    ```typescript
    // DataFetcher.ts
    export function fetchData() { /* ... */ }
    ```

### Commit Messages
- Follow **Conventional Commits**.
- Use prefixes, such as `docs`, to indicate the type of change.
  - Example:
    ```
    docs: update README with installation steps
    ```
- Keep commit messages concise (average ~50 characters).

## Workflows

### Documenting Changes
**Trigger:** When updating or adding documentation.
**Command:** `/docs-update`

1. Make your documentation changes.
2. Stage the changes:
   ```
   git add .
   ```
3. Commit using the conventional prefix:
   ```
   git commit -m "docs: describe new API endpoint"
   ```
4. Push your changes:
   ```
   git push
   ```

## Testing Patterns

- Test files follow the `*.test.*` naming convention.
  - Example: `UserProfile.test.ts`
- The testing framework is not specified; ensure your tests are colocated with the code or in a dedicated test directory.
- Example test file structure:
  ```typescript
  // UserProfile.test.ts
  import { getUserProfile } from './UserProfile';

  describe('getUserProfile', () => {
    it('returns the correct user data', () => {
      // test implementation
    });
  });
  ```

## Commands
| Command       | Purpose                                      |
|---------------|----------------------------------------------|
| /docs-update  | Standardize documentation update workflow    |
```
