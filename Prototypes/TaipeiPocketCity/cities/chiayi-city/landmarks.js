// The station's pale arched central hall, flat art-deco cornice and low
// continuous canopy sit on the original railway station footprint.
function chiayiStation(){
  const b=findBuilding('w286891391');
  const r=b.ring, facade='#d4c5a0', ledge='#ded0ad', glass='#718482';
  const main=rect(-1.25,0,17.9,24.5);
  const wings=block(r,0,5.05,{facade:'civic',wall:facade,flatRoof:'#a9a197',trim:ledge,shop:'none',floor:3.4,bay:3.6});
  const plinth=block(main,4.8,11.7,{facade:'plain',wall:facade,flatRoof:'#a49c90',bay:40,shop:'none'});
  const cornice=block(rect(-1.25,0,18.18,24.82),11.57,12.1,
    {facade:'plain',wall:'#beaa85',flatRoof:'#a49c90',bay:40,shop:'none'});
  const canopy=rect(7.36,.2,5.6,58.6);
  const arch=(at,mid,r,foot,spring,color)=>{
    const top=Array.from({length:11},(_,i)=>at(mid+r*Math.cos(Math.PI*i/10),spring+r*Math.sin(Math.PI*i/10)));
    return shape([at(mid-r,foot),at(mid+r,foot),...top],color,.38);
  };
  const drawing=()=>{
    const ring=ccw(main);
    return ring.map((a,i)=>{
      const c=ring[(i+1)%ring.length],dx=c[0]-a[0],dy=c[1]-a[1],L=Math.hypot(dx,dy),n=[dy/L,-dx/L,0];
      if(!vis(n))return '';
      const at=(s,z)=>[a[0]+s*dx/L+n[0]*.046,a[1]+s*dy/L+n[1]*.046,z];
      const count=4, bay=L/count;
      return Array.from({length:count},(_,j)=>{
        const m=bay*(j+.5),w=Math.min(1.17,bay*.31);
        return arch(at,m,w+.19,6.03,9.47,'#ad986e')+arch(at,m,w,6.16,9.46,glass)
          +edge(at(m,6.13),at(m,10.23),'#cabb9f',.13)+edge(at(m-w,8.33),at(m+w,8.33),'#cabb9f',.14);
      }).join('');
    }).join('');
  };
  return obj(r,14.35,()=>{
    const facing=vis([1,0,0]);
    const posts=Array.from({length:12},(_,i)=>{
      const y=-28.4+i*5.15,r=rect(9.62,y,.42,.4);
      return loft(atZ(r,0),atZ(r,4.18),n=>tone(n,soft('#b9b3a0')));
    }).join('');
    const canopyFront=(()=> {
      const at=(x,z)=>[10.19,x,z];
      let band=shape([[10.17,-29.1,3.76],[10.17,29.5,3.76],[10.17,29.5,4.75],[10.17,-29.1,4.75]],'#b0a698',.53);
      for(let i=0;i<10;i++){
        const m=-26.2+i*5.72,w=2.6;
        const arc=Array.from({length:11},(_,k)=>at(m+w*Math.cos(k*Math.PI/10),2.68+1.04*Math.sin(k*Math.PI/10)));
        band+=shape([at(m-w,3.77),at(m+w,3.77),...arc],'#a8a18e',.42);
      }
      return band;
    })();
    const roof=shape(atZ(canopy,4.76),'#a99d88',.61);
    const sign=Array.from({length:5},(_,i)=>{
      const y=-8.5+i*3.65,x=7.23;
      const panel=[[x,y-1.0,12.69],[x,y+1,12.69],[x,y+1,14.08],[x,y-1,14.08]];
      return stick([x,y,12.1],[x,y,12.78],.06,'#8b9290')+shape(panel,'#dddacf',.36)+
        shape([[x+.01,y-.61,13],[x+.01,y+.61,13],[x+.01,y+.61,13.76],[x+.01,y-.61,13.76]],'#647894',.1);
    }).join('');
    return wings.draw()+plinth.draw()+drawing()+cornice.draw()+posts+roof+(facing?canopyFront:'')+sign;
  });
}
const LANDMARKS=[{name:'嘉義車站',ids:['w286891391'],build:chiayiStation}];
