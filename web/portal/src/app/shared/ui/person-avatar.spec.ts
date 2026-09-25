import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { PersonAvatar } from './person-avatar';

describe('PersonAvatar photo priority', () => {
  beforeEach(() => TestBed.configureTestingModule({
    imports: [PersonAvatar],
    providers: [provideHttpClient(), provideHttpClientTesting(), { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, useFixtures: false } }],
  }));
  it('keeps the fallback on a missing photo and prefers a returned personal photo', () => {
    const fixture = TestBed.createComponent(PersonAvatar);
    fixture.componentRef.setInput('childId', '7');
    fixture.componentRef.setInput('gender', 'F');
    fixture.componentRef.setInput('birthDate', '2000-01-01');
    fixture.detectChanges();
    const http = TestBed.inject(HttpTestingController);
    http.expectOne('/api/v1/children/7/photo').flush(new Blob(), { status: 404, statusText: 'Not Found' });
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('img').getAttribute('src')).toBe('assets/avatars/adult-woman.png');
    fixture.componentRef.setInput('childId', '8');
    fixture.detectChanges();
    http.expectOne('/api/v1/children/8/photo').flush(new Blob(['image'], { type: 'image/png' }));
    fixture.detectChanges();
    const img: HTMLImageElement = fixture.nativeElement.querySelector('img');
    expect(img.getAttribute('src')).toMatch(/^blob:/);
    img.dispatchEvent(new Event('error'));
    fixture.detectChanges();
    expect(img.getAttribute('src')).toBe('assets/avatars/adult-woman.png');
    http.verify();
    fixture.destroy();
  });
});
