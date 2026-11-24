import {recoveredFronts} from './taipei-shopfront-recoveries.js';

const recoveredByID=new Map(recoveredFronts.map(row=>[row.id,row]));

export function frontageSearchRow(row){
  const recovered=row[5]===null&&recoveredByID.get(row[6]);
  return recovered?[row[0],row[1],recovered.street,...recovered.center,recovered.angle,row[6]]:row.slice(0,7);
}

export function completeFrontagePack(pack,rows){
  if(!Array.isArray(rows))throw Error('Invalid Pocket City frontage pack');
  const additions=recoveredFronts.filter(r=>r.pack===pack&&!rows.some(primary=>primary.id===r.id));
  return additions.length?rows.concat(additions):rows;
}
