import { TestBed } from '@angular/core/testing';
import { of } from 'rxjs';
import { AvatarEditor, avatarSaveError } from './avatar-editor';
import { HttpErrorResponse } from '@angular/common/http';
import { UserAvatars } from './user-avatar';

describe('Avatar crop editor',()=>{
  it('explains missing server support and disabled storage instead of suggesting a blind retry',()=>{
    expect(avatarSaveError(new HttpErrorResponse({status:404}))).toContain('لم تُفعّل');
    expect(avatarSaveError(new HttpErrorResponse({status:503}))).toContain('تخزين الصور غير متاح');
    expect(avatarSaveError(new HttpErrorResponse({status:403}))).toContain('لا يمكنك');
  });
  it('previews a selected image, applies zoom and saves the cropped JPEG attachment',async()=>{
    const save=jasmine.createSpy('save').and.returnValue(of({}));
    TestBed.configureTestingModule({providers:[{provide:UserAvatars,useValue:{save}}]});
    const fixture=TestBed.createComponent(AvatarEditor);fixture.componentRef.setInput('userId',8);fixture.detectChanges();
    const original=document.createElement('canvas');original.width=800;original.height=400;
    original.getContext('2d')!.fillRect(0,0,800,400);
    const blob=await new Promise<Blob>(resolve=>original.toBlob(value=>resolve(value!),'image/png'));
    const input=fixture.nativeElement.querySelector('input[type=file]') as HTMLInputElement;
    const transfer=new DataTransfer();transfer.items.add(new File([blob],'portrait.png',{type:'image/png'}));input.files=transfer.files;
    await (fixture.componentInstance as any).pick({target:input});fixture.detectChanges();await fixture.whenStable();
    expect(fixture.nativeElement.querySelector('dialog').open).toBeTrue();
    const range=fixture.nativeElement.querySelector('input[type=range]') as HTMLInputElement;
    range.value='2';range.dispatchEvent(new Event('input'));fixture.detectChanges();
    const saved=new Promise<void>(resolve=>fixture.componentInstance.saved.subscribe(()=>resolve()));
    (fixture.nativeElement.querySelector('footer button') as HTMLButtonElement).click();
    await saved;fixture.detectChanges();
    expect(save).toHaveBeenCalledTimes(1);
    const [id,image]=save.calls.mostRecent().args;expect(id).toBe(8);expect(image.type).toBe('image/jpeg');
    const bitmap=await createImageBitmap(image);expect(bitmap.width).toBe(512);expect(bitmap.height).toBe(512);bitmap.close();
    expect(fixture.nativeElement.querySelector('dialog')).toBeNull();
  });
});
