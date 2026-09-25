import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { HBH_CONFIG } from '../config/app-config';
import { UserAvatars } from './user-avatar';
import { cropGeometry } from './avatar-crop';

describe('Account avatars', () => {
  let http: HttpTestingController;
  beforeEach(() => {
    TestBed.configureTestingModule({providers:[provideHttpClient(),provideHttpClientTesting(),{provide:HBH_CONFIG,useValue:{apiBaseUrl:''}}]});
    http=TestBed.inject(HttpTestingController);
  });
  afterEach(()=>http.verify());
  it('shares saved photos immediately and clears cached photos on account changes',()=>{
    const service=TestBed.inject(UserAvatars);
    service.reset(8);service.load(8);service.load(8);
    http.expectOne('/api/v1/users/8/photo').flush(new Blob(['photo'],{type:'image/jpeg'}));
    const old=service.urls()[8];expect(old.startsWith('blob:')).toBeTrue();
    const revoke=spyOn(URL,'revokeObjectURL');
    const cropped=new Blob(['new'],{type:'image/jpeg'});
    service.save(8,cropped).subscribe();
    const upload=http.expectOne('/api/v1/users/8/photo');
    expect(upload.request.body.get('file').type).toBe('image/jpeg');
    upload.flush({});
    http.expectOne('/api/v1/users/8/photo').flush(cropped);
    expect(service.urls()[8]).not.toBe(old);expect(revoke).toHaveBeenCalledWith(old);
    service.reset(9);expect(service.urls()).toEqual({});
    service.load(8);http.expectOne('/api/v1/users/8/photo').flush(null,{status:404,statusText:'Not Found'});
    expect(service.urls()).toEqual({});
  });
  it('reloads the saved photo from the server after sign out and sign in', () => {
    const service = TestBed.inject(UserAvatars);
    const photo = new Blob(['persisted'], { type: 'image/jpeg' });
    service.reset(8);
    service.save(8, photo).subscribe();
    http.expectOne('/api/v1/users/8/photo').flush({});
    http.expectOne('/api/v1/users/8/photo').flush(photo);
    service.reset(null); service.reset(8); service.load(8);
    http.expectOne('/api/v1/users/8/photo').flush(photo);
    expect(service.urls()[8]).toBeTruthy();
  });
  it('does not report a successful save if the server cannot read the uploaded photo', () => {
    const service = TestBed.inject(UserAvatars);
    const saved = jasmine.createSpy('saved'), failed = jasmine.createSpy('failed');
    service.save(8,new Blob(['photo'])).subscribe({next:saved,error:failed});
    http.expectOne('/api/v1/users/8/photo').flush({});
    http.expectOne('/api/v1/users/8/photo').flush(null,{status:404,statusText:'Not Found'});
    expect(saved).not.toHaveBeenCalled(); expect(failed).toHaveBeenCalled();
    expect(service.urls()[8]).toBeUndefined();
  });
  it('clears a removed users photo so every consumer returns to initials', () => {
    const service = TestBed.inject(UserAvatars);
    service.load(8);
    http.expectOne('/api/v1/users/8/photo').flush(new Blob(['photo'], { type: 'image/jpeg' }));
    expect(service.urls()[8]).toBeTruthy();
    service.load(8, true);
    http.expectOne('/api/v1/users/8/photo').flush(null, { status: 404, statusText: 'Not Found' });
    expect(service.urls()[8]).toBeUndefined();
  });
  it('keeps every crop inside landscape and portrait sources at all zoom and position extremes',()=>{
    for(const [width,height] of [[1200,600],[600,1200]]) {
      for(const zoom of [1,2,4]) for(const x of [0,50,100]) for(const y of [0,50,100]) {
        const g=cropGeometry(width,height,zoom,x,y);
        expect(g.sx).toBeGreaterThanOrEqual(0);expect(g.sy).toBeGreaterThanOrEqual(0);
        expect(g.sx+g.side).toBeLessThanOrEqual(width);expect(g.sy+g.side).toBeLessThanOrEqual(height);
      }
    }
    expect(cropGeometry(1200,600,1,50,50)).toEqual({sx:300,sy:0,side:600});
  });
});

