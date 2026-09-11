#!/bin/zsh
# $1 = output file, $2 = active label, $3 = "emp" for 2-tab employee nav
ICON_DASH='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7" rx="1.6"/><rect x="14" y="3" width="7" height="7" rx="1.6"/><rect x="3" y="14" width="7" height="7" rx="1.6"/><rect x="14" y="14" width="7" height="7" rx="1.6"/></svg>'
ICON_SALE='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="4.5"/><path d="M12 8.2v7.6M8.2 12h7.6"/></svg>'
ICON_ORD='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 3h13v18l-2.6-1.6L13.4 21 11 19.4 8.6 21 6 19.4 5.5 21z"/><path d="M9 8.4h6M9 12.4h6"/></svg>'
ICON_MORE='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 12h.01M12 12h.01M19 12h.01"/></svg>'
cls() { [[ "$2" == "$1" ]] && echo ' class="on"' || echo ""; }
{
printf '  <div class="nav">\n'
if [[ "$3" == "emp" ]]; then
  printf '    <div%s>%s<span>New Sale</span></div>\n' "$(cls 'New Sale' "$2")" "$ICON_SALE"
  printf '    <div%s>%s<span>Orders</span></div>\n' "$(cls 'Orders' "$2")" "$ICON_ORD"
else
  printf '    <div%s>%s<span>Dashboard</span></div>\n' "$(cls 'Dashboard' "$2")" "$ICON_DASH"
  printf '    <div%s>%s<span>New Sale</span></div>\n' "$(cls 'New Sale' "$2")" "$ICON_SALE"
  printf '    <div%s>%s<span>Orders</span></div>\n' "$(cls 'Orders' "$2")" "$ICON_ORD"
  printf '    <div%s>%s<span>More</span></div>\n' "$(cls 'More' "$2")" "$ICON_MORE"
fi
printf '  </div>\n'
} > "$1"
