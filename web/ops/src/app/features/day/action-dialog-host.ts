import { NgComponentOutlet } from '@angular/common';
import {
  ChangeDetectionStrategy, Component, Injector, computed, inject,
} from '@angular/core';
import { ActivatedRoute, convertToParamMap } from '@angular/router';
import { of } from 'rxjs';

import { EmbeddedAction, EmbeddedResource } from '../../core/ops/action-request';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { ResourceScreen } from '../resource/resource-screen';
import { DayScreen } from './day-screen';

/**
 * Draws the dialog the service was asked to open, anywhere in the console.
 *
 * It does so by creating the screen that owns the dialog in "embedded"
 * mode - DayScreen for a day action, ResourceScreen for a resource editor -
 * given its spec and the request through a stand-in ActivatedRoute instead
 * of the router's. The screen reads `data['embedded']` (or
 * `data['embeddedResource']`), skips its list and filters, opens the dialog
 * at once and reports back through `onClose`. Nothing about either dialog -
 * fields, checks, submit - lives anywhere but in the screen that owns it,
 * which is the point: one dialog, drawn from several places.
 */
@Component({
  selector: 'hbh-action-dialog-host',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [NgComponentOutlet],
  template: `
    @if (embed(); as current) {
      <ng-container *ngComponentOutlet="dayScreen; injector: injectorFor(current)" />
    }
    @if (embedResource(); as current) {
      <ng-container *ngComponentOutlet="resourceScreen; injector: injectorForResource(current)" />
    }
  `,
})
export class ActionDialogHost {
  private readonly svc = inject(ActionDialogService);
  private readonly parent = inject(Injector);
  protected readonly dayScreen = DayScreen;
  protected readonly resourceScreen = ResourceScreen;
  protected readonly embed = computed(() => this.svc.active());
  protected readonly embedResource = computed(() => this.svc.activeResource());

  private cache: { key: object; injector: Injector } | null = null;
  private cacheResource: { key: object; injector: Injector } | null = null;

  /** One injector per open dialog, so the outlet does not re-create the screen on every check. */
  protected injectorFor(embed: EmbeddedAction): Injector {
    if (this.cache?.key === embed) {
      return this.cache.injector;
    }
    const injector = this.stub({ spec: embed.spec, embedded: embed });
    this.cache = { key: embed, injector };
    return injector;
  }

  protected injectorForResource(embed: EmbeddedResource): Injector {
    if (this.cacheResource?.key === embed) {
      return this.cacheResource.injector;
    }
    const injector = this.stub({ specs: [embed.spec], embeddedResource: embed });
    this.cacheResource = { key: embed, injector };
    return injector;
  }

  private stub(data: Record<string, unknown>): Injector {
    const route = {
      snapshot: {
        data,
        queryParamMap: convertToParamMap({}),
        paramMap: convertToParamMap({}),
        queryParams: {},
        params: {},
      },
      queryParamMap: of(convertToParamMap({})),
      paramMap: of(convertToParamMap({})),
    };
    return Injector.create({
      providers: [{ provide: ActivatedRoute, useValue: route }],
      parent: this.parent,
    });
  }
}
