/** Lost characters cannot be recovered in the client. Keep the record identifiable
 * without inventing a clinical title or modifying the original report. */
export function reportDisplayTitle(title: string, id: number): string {
  return !title?.trim() || /\?{3,}|\uFFFD/.test(title)
    ? `تقرير رقم ${id} — العنوان غير متاح`
    : title;
}
