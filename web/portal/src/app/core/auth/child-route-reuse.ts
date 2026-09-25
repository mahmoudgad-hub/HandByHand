import { Injectable } from '@angular/core';
import { ActivatedRouteSnapshot, BaseRouteReuseStrategy } from '@angular/router';

/** Recreate the current screen when switching children; keep the shell mounted. */
@Injectable({ providedIn: 'root' })
export class ChildRouteReuse extends BaseRouteReuseStrategy {
  refreshingChild = false;

  override shouldReuseRoute(future: ActivatedRouteSnapshot, current: ActivatedRouteSnapshot): boolean {
    if (this.refreshingChild && future.routeConfig && !future.routeConfig.children) return false;
    return super.shouldReuseRoute(future, current);
  }
}
