// from http://www.jacos.nl/jacos_html/spline/

/* bezier-spline.js
 *
 * computes cubic bezier coefficients to generate a smooth
 * line through specified points. couples with SVG graphics 
 * for interactive processing.
 *
 * For more info see:
 * http://www.particleincell.com/2012/bezier-splines/ 
 *
 * Lubos Brieda, Particle In Cell Consulting LLC, 2012
 * you may freely use this algorithm in your codes however where feasible
 * please include a link/reference to the source article
 * 
 * correction by Jaco Stuifbergen:
 * in computeControlPoints:
 *	r[n-1] = 3*K[n-1]; // otherwise, the curvature on the last knot is wrong
 * 
 * modification: 
 * the distance of control points is proportional to the distance between knots
I.e. if D(x1,x2) is the distance between x1 and x2,
 and P1[i] , P2[i] are the control points between knots K[i] and K[i+1]
then 
 D(P2[i-1],K[i]) / D(K[i-1],K[i]) = D(K[i],P1[i]) / D(K[i],K[i+1])
 */ 

var svg=document.documentElement /*svg object*/
var nPaths = 6 /* number of knots = nPaths +1 */
var S=new Array() /*splines*/
var V=new Array() /*vertices*/
// var movingKnot 	/*current object*/
var x0,y0	/*svg offset*/
var colours = [ "blue", "red", "green", "brown", "yellow", "magenta"]
var pathIdPrefix = "pathNr_"
var knotIdPrefix = "knotNr_"
var pathWidth = 4
var minWeight = 1 // the calculation of a curve becomes impossible if a distance is 0
/*saves elements as global variables*/
function init()
{
	/*create control points*/
	V[0] = createKnot(60,80,0);
	V[1] = createKnot(490,70,1);
	V[2] = createKnot(485,75,1);
	V[3] = createKnot(800,140,2);
	V[4] = createKnot(280,155,4);
	V[5] = createKnot(260,170,5);
	V[6] = createKnot(330,410,6);
	
	/*create splines*/
	createAllPaths()

	updateSplines();

	//createText(200,100,"testje","tekst voor test")
}

function removeAllPaths()
{
	var i
	for (i=nPaths-1;0<=i ; i--)
	{	 S[i].remove()
	}
}

function createAllPaths()
{
	var i
	for (i=0; i<nPaths ; i++)
	{	S[i] = createPath(colours[i%colours.length], pathWidth,i);	
	}
}
/*creates and adds an SVG circle to represent knots*/
function createKnot(x,y,knotNumber)
{ 
	var Circ=document.createElementNS("http://www.w3.org/2000/svg","circle")
	Circ.setAttributeNS(null,"id",knotIdPrefix+knotNumber)
	Circ.setAttributeNS(null,"r",22)
	Circ.setAttributeNS(null,"cx",x)
	Circ.setAttributeNS(null,"cy",y)
	Circ.setAttributeNS(null,"fill","grey")
	Circ.setAttributeNS(null,"fill-opacity","0.1")
	Circ.setAttributeNS(null,"stroke","black")
	Circ.setAttributeNS(null,"stroke-opacity","1.0")
	Circ.setAttributeNS(null,"stroke-width","3")
	Circ.setAttributeNS(null,"onmouseover","evt.target.setAttribute('fill-opacity', '0.5')")
	Circ.setAttributeNS(null,"onmouseout","evt.target.setAttribute('fill-opacity','0.1');")
	Circ.setAttributeNS(null,"onmousedown","knotClicked(evt)")
	// Circ.setAttributeNS(null,"onmousedown","removeKnot(evt)")
	// Circ.setAttributeNS(null, "onmouseup","removeKnot(evt);drop(evt)")
	svg.appendChild(Circ)	
	return Circ
}

/*creates and adds an SVG path without defining the nodes*/
function createPath(color,width,id)
{		
	width = (typeof width == 'undefined' ? "4" : width);
	var P=document.createElementNS("http://www.w3.org/2000/svg","path")
	P.setAttributeNS(null,"id",pathIdPrefix+id)
	P.setAttributeNS(null,"fill","none")
	P.setAttributeNS(null,"stroke",color)
	P.setAttributeNS(null,"stroke-width",width)
	P.setAttributeNS(null,"onmousedown","pathClicked(evt)")
	svg.appendChild(P)
	return P
}

/* remove an object */
function remove(id)
{
	var parent = event.target.parentNode
	parent.removeChild(id)

}

/*from http://www.w3.org/Graphics/SVG/IG/resources/svgprimer.html*/
function knotClicked_old(evt)
/* wordt thans niet gebruikt (niet af)
doel: bij linker-muisknop: verwijder knoop
bij rechter-muisknop: verplaats knoop
*/
{
	/*SVG positions are relative to the element but mouse 
	  positions are relative to the window, get offset*/
	x0 = getOffset(svg).left; 
	y0 = getOffset(svg).top; 
	
	var id = parseInt(evt.target.getAttribute("id").slice(knotIdPrefix.length))
	evt.target.setAttributeNS(null, "fill","cyan")
	evt.target.setAttributeNS(null, "stroke-opacity","0.2")
	evt.target.setAttributeNS(null, "debugInfo","id is "+id)
	svg.setAttribute("onmousemove","moveKnot(evt,"+id+")")
	// svg.setAttribute("onmouseup","drop(evt)")	
	
	/* removeKnot werkt niet na moveKnot!*/
	/* blijkbaar wordt niet het juiste 'evt' toegekend bij "onmouseup" nadat "onmousemove" plaatsgevonden heeft
	*/
	// svg.setAttribute("onmouseup","removeKnot(evt);drop(evt)")	

	// removeKnot(evt)
}
function knotClicked(evt)
/* change colour of the knot
set onmouseup("removeKnot(evt,"+id+")")
set onmouseout("drop()")
doel: bij linker-muisknop: verwijder knoop
bij rechter-muisknop: verplaats knoop
*/
{
	var id = parseInt(evt.target.getAttribute("id").slice(knotIdPrefix.length))
	evt.target.setAttributeNS(null, "fill","red")
	// evt.target.setAttributeNS(null, "stroke-opacity","0.2")
	// evt.target.setAttributeNS(null, "debugInfo","id is "+id)
	svg.setAttribute("onmouseup","removeKnot(evt,"+id+")")
	svg.setAttribute("onmouseout","drop(evt,"+id+")")
}

/*creates and adds an empty text element - not used*/
function createText(x,y, id, text)
{
	var newObj=document.createElementNS("http://www.w3.org/2000/svg","text")
	// newObj.setAttributeNS(null,"text",text)
	newObj.setAttributeNS(null,"id",id)
	newObj.setAttributeNS(null,"x",x)
	newObj.setAttributeNS(null,"y",y)
	newObj.setAttributeNS(null,"color","black")
	svg.appendChild(newObj)	
	document.getElementById(id).innerHTML =text
	// newObj.innerHTML =text
	
	// window.alert("textbox voor x="+x+" y="+y)
	return newObj
}

/*called on mouse move, updates dragged circle and recomputes splines*/
function moveKnot(evenement,id)
{
	x = evenement.clientX-x0;
	y = evenement.clientY-y0;
	
	/*move the current handle*/
	/* applies to circles */
	V[id].setAttributeNS(null,"cx",x)
	V[id].setAttributeNS(null,"cy",y)
	// evt.target.setAttributeNS(null,"cx",x)
	// evt.target.setAttributeNS(null,"cy",y)
	updateSplines();
}

/*called on mouse up, removes circle and updates splines*/
function removeKnot(evenement)
/* applies to circles */
{
	var condemnedKnot=evenement.target
	var id = parseInt(condemnedKnot.getAttribute("id").slice(knotIdPrefix.length))
	// window.alert("id van de knoop is "+ id)
	// document.getElementById("testje").innerHTML =("id van de knoop is "+ id)
	condemnedKnot.remove()
	// evt.target.remove() // fout! evt is null als deze functie aangeroepen wordt door knotClicked
	for (i=id; i<nPaths ; i++)
	{
		V[i] = V[i+1]
		V[i].setAttributeNS(null,"id",knotIdPrefix+(i))
	}
	
	nPaths--
	S[nPaths].remove()
	updateSplines();
	// drop() // maakt "onmousemove" inactief
}


/*called on mouse move, updates dragged circle and recomputes splines*/
function pathClicked(evt)
{
	/*SVG positions are relative to the element but mouse 
	  positions are relative to the window, get offset*/
	x0 = getOffset(svg).left; 
	y0 = getOffset(svg).top; 

	// CurrO=evt.target
	
	x = evt.clientX-x0;
	y = evt.clientY-y0;
	
	var id = parseInt(evt.target.getAttribute("id").slice(pathIdPrefix.length))

	insertKnot(id,x,y)

	// insertPath(id)
	// insertPath(nPaths-1)
	// create all paths again, so they will be on top of the Knots
	removeAllPaths()
	nPaths++ // we have added a knot, so we must add a path
	createAllPaths()
	updateSplines()

	/* onmousemove events must perform an action on this object */
	// movingKnot = V[id+1] // global variable used in moveKnot
	
	/* set onmousemove */ 
	svg.setAttribute("onmousemove","moveKnot(evt,"+(id+1)+")")

	/* after onmouseup, the knot should not move*/
	svg.setAttribute("onmouseup","drop(evt,"+(id+1)+")")	
}

function insertKnot(id,x,y)
{
	/* distance to the previous and to the next Knot */
	
	/* inserts a knot between V[id] and V[id+1]
	 * (if the distance from (x,y) to those knots is sufficient)*/
	/* pre-condition: 
	V[0] to V[nPaths-1] exist
	id < nPaths
	*/
	
	/* shift array of knots */
	for (i=nPaths+1 ; id+1 < i ; i--)
	{	V[i]=V[i-1];
		V[i].setAttributeNS(null,"id",knotIdPrefix+i);
	}
	/* add knot */
	V[id+1] = createKnot(x,y,id+1);
}

function insertPath(id)
{
	/* inserts a path between S[id] and S[id+1] if both exist, otherwise after S[id]*/
	/* pre-condition: 
	S[0] to S[nPaths-1] exist
	id < nPaths
	*/
	/* shift array of knots */
	/* note: The highest Id for a path is pathIdPrefix+(nPaths-1) */
	
	for (i=nPaths; id+1 < i ; i--)
	{	S[i]=S[i-1];
		S[i].setAttributeNS(null,"id",pathIdPrefix+i);
	}
	/* add path */
	S[id+1] = createPath(colours[(id+1)%colours.length],pathWidth,id+1);
	nPaths ++
}

/*called on mouse up event*/
function drop(evenement, id)
{
	// svg  = document.getElementsByTagName('svg')[0];
	svg.setAttributeNS(null, "onmousemove",null)
	svg.setAttributeNS(null, "onmouseup",null)
	svg.setAttributeNS(null, "onmouseout",null)
	V[id].setAttributeNS(null, "fill","black")
	V[id].setAttributeNS(null, "fill-opacity","0.1")
	V[id].setAttributeNS(null, "stroke-opacity","1.0")

}

/*code from http://stackoverflow.com/questions/442404/dynamically-retrieve-html-element-x-y-position-with-javascript*/
function getOffset( el ) 
{
    var _x = 0;
    var _y = 0;
    while( el && !isNaN( el.offsetLeft ) && !isNaN( el.offsetTop ) ) {
        _x += el.offsetLeft - el.scrollLeft;
        _y += el.offsetTop - el.scrollTop;
        el = el.offsetParent;
    }
    return { top: _y, left: _x };
}

/* computes the distance (along a straight line) between the knots */
function distances(x,y) // V is the array of knots
{
	var i, nPaths, result
	
	nPaths = x.length-1
	result = new Array(nPaths)
	for (i=0;i<nPaths;i++)
	{
		/* calculate Euclidean distance */
		result[i]=Math.sqrt((x[i+1]-x[i])^2 +(y[i+1]-y[i])^2)
	}
		
	return result
}	

/*computes spline control points*/
function updateSplines()
{	
	var x, y /* (x,y) coordinates of the knots*/
	var weights // equal to the distances between knots. If knots are nearer, the 3rd derivative can be higher
	var px, py // coordinates of the intermediate control points

	// tijdelijk, voor foutopsporing
	var d1,d2
	
	/*grab (x,y) coordinates of the knots */
	x=new Array();
	y=new Array();
	for (i=0;i<=nPaths;i++)
	{
		/*use parseInt to convert string to int*/
		x[i]=parseInt(V[i].getAttributeNS(null,"cx"))
		y[i]=parseInt(V[i].getAttributeNS(null,"cy"))
	}
	//weights = distances (x,y)	
	weights = new Array(nPaths)
	for (i=0;i<nPaths;i++)
	{
		/* calculate Euclidean distance */
		weights[i]=Math.sqrt(Math.pow((x[i+1]-x[i]),2) +Math.pow((y[i+1]-y[i]),2))
		// if the weight is too small, the calculation becomes instable	
		weights[i] = minWeight<weights[i]?weights[i]:minWeight
	}
	weights[nPaths]=weights[nPaths-1]
		
	/* berekenen van de curve */
	px = computeControlPointsBigWThomas(x,weights);
	py = computeControlPointsBigWThomas(y,weights);
	
	/*updates path settings, the browser will draw the new spline*/
	for (i=0;i<nPaths;i++)
		S[i].setAttributeNS(null,"d",
			pathDescription(x[i],y[i],px.p1[i],py.p1[i],px.p2[i],py.p2[i],x[i+1],y[i+1]));
	
}

function verschilArrayNorm(arr1,arr2)
{
	var i,n, result
	n=arr1.length
	
	result = 0
	for(i=0 ; i<n ; i++)
	{
		result+=Math.abs(arr1[i]-arr2[i])	
	}
	return result
}
function verschilArray(arr1,arr2)
{
	var i,n, result
	n=arr1.length
	
	result = new Array(n)
	for(i=0 ; i<n ; i++)
	{
		result[i]=arr1[i]-arr2[i]	
	}
	return result
}
function addDebugInfo(data, legend, label)
{
	var debugInfo = "" 
	var i, nPath
	nPath = data.length

	for (i=0;i<nPath;i++)
	{
		debugInfo = debugInfo + " "+label+"["+i+"]="+data[i]
	}
	
	V[0].setAttributeNS(null,legend, debugInfo)//debugInfo)	
}
/*creates formated path string for SVG cubic path element*/
function pathDescription(x1,y1,px1,py1,px2,py2,x2,y2)
{
	return "M "+x1+" "+y1+" C "+px1+" "+py1+" "+px2+" "+py2+" "+x2+" "+y2;
}

function computeControlPointsW(K,W)
/*computes control points given knots K, this is the brain of the operation*/
/* this version makes the distance of the control points proportional to the distance between the end points.
I.e. if D(x1,x2) is the distance between x1 and x2,
 and P1[i] , P2[i] are the control points between knots K[i] and K[i+1]
then 
 D(P2[i-1],K[i]) / D(K[i-1],K[i]) = D(K[i],P1[i]) / D(K[i],K[i+1])

The calculation of the second derivative has been adapted in 2 ways:
If W[i]=D(K[i-1],K[i])/D(K[i+1],K[i]) 
1) 	P2[i-1] = P1[i-1]*W +K[i]*(W[i]+1)
2)	S''[i](0)*W[i]*W[i]=S''[i-1](1)
*/

// required: W has the same length als K 
{
	var p1, p2, n
	var frac_i, frac_iplus1

	p2=new Array();
	n = K.length;
	
	/*rhs vector*/
	a=new Array();
	b=new Array();
	c=new Array();
	r=new Array();
	
	frac_i=W[0]/W[1]

	/*left most segment*/
	a[0]=0; // outside the matrix
	b[0]=2;
	c[0]=W[0]/W[1]
	r[0] = K[0]+(1+W[0]/W[1])*K[1];
	
	/*internal segments*/
	// required: W has the same length als K 
	for (i = 1; i < n - 1; i++)
	{
		a[i]=1*W[i]*W[i];
		b[i]=2*W[i-1]*(W[i-1]+W[i]);
		c[i]=W[i-1]*W[i-1]*W[i]/W[i+1];
		r[i] = Math.pow(W[i-1]+W[i],2) * K[i] + Math.pow(W[i-1],2)*(1+W[i]/W[i+1]) * K[i+1];

	}
		
	/*right segment*/
	a[n-1]=1;
	b[n-1]=2;
	c[n-1]=0; // outside the matrix
	r[n-1] = (1+2*W[n-1]/W[n-2])*K[n-1]; // W[n-1] must be defined 
	// required: W has the same length als K 
	
	/*solves Ax=b with the Thomas algorithm (from Wikipedia)*/
	p1=Thomas(r,a,b,c)
	
	/*we have p1, now compute p2*/
	for (i=0;i<n-1;i++)
	{	//p2[i]=2*K[i+1]-p1[i+1];
		p2[i]=K[i+1]* (1+W[i]/W[i+1])-p1[i+1]*(W[i]/W[i+1]);
	}
	//p2[n-1]=2*K[n]-p1[n]
	/* the last element of p1 is only used to calculate p2 */
	p1.splice(n-1,1) // remove the last element
	return {p1:p1, p2:p2};
}

/*computes control points given knots K, this is the brain of the operation*/
/* this version makes the distance of the control points proportional to the distance between the end points.
I.e. if D(x1,x2) is the distance between x1 and x2,
 and P1[i] , P2[i] are the control points between knots K[i] and K[i+1]
then 
 D(P2[i-1],K[i]) / D(K[i-1],K[i]) = D(K[i],P1[i]) / D(K[i],K[i+1])

The calculation of the second derivative has been adapted in 2 ways:
If W[i]=D(K[i-1],K[i])/D(K[i+1],K[i]) 
1) 	P2[i-1] = P1[i-1]*W +K[i]*(W[i]+1)
2)	S''[i](0)*W[i]*W[i]=S''[i-1](1)
*/

function computeControlPointsBigWThomas(K,W)
{
	var p, p1, p2
	p = new Array();

	p1=new Array();
	p2=new Array();
	n = K.length-1;
	
	/*rhs vector*/
	a=new Array();
	b=new Array();
	c=new Array();
	d=new Array();
	r=new Array();
	
	/*left most segment*/
	a[0]=0; // outside the matrix
	b[0]=2;
	c[0]=-1;
	d[0]=0
	r[0] = K[0]+0;// add curvature at K0
	
	/*internal segments*/
	for (i = 1; i < n ; i++)
	{
		a[2*i-1]=1*W[i]*W[i];
		b[2*i-1]=-2*W[i]*W[i];
		c[2*i-1]=2*W[i-1]*W[i-1];
		d[2*i-1]=-1*W[i-1]*W[i-1]
		r[2*i-1] = K[i]*((-W[i]*W[i]+W[i-1]*W[i-1]))//

		a[2*i]=W[i];
		b[2*i]=W[i-1];
		c[2*i]=0;
		d[2*i]=0; // note: d[2n-2] is already outside the matrix
		r[2*i] = (W[i-1]+W[i])*K[i];

	}
			
	/*right segment*/
	a[2*n-1]=-1;
	b[2*n-1]=2;
	r[2*n-1]=K[n];// curvature at last point

	// the following array elements are not in the original matrix, so they should not be used:
	c[2*n-1]=0; // outside the matrix
	d[2*n-2]=0; // outside the matrix
	d[2*n-1]=0; // outside the matrix

	/*solves Ax=b with the Thomas algorithm (from Wikipedia)*/
	p = Thomas4(r,a,b,c,d)

	/*re-arrange the array*/
	for (i=0;i<n;i++)
	{
		p1[i]=p[2*i];
		p2[i]=p[2*i+1];
	}
	
	return {p1:p1, p2:p2};
}

/*solves Ax=b with the Thomas algorithm (from Wikipedia)*/
/* essentially, a Gaussian elimination for a tri-diagonal matrix
*/
function Thomas(r,a,b,c)
{
	var x,i,n
	n = r.length
	for (i = 1; i < n; i++)
	{
		m = a[i]/b[i-1];
		b[i] = b[i] - m * c[i - 1];
		r[i] = r[i] - m*r[i-1];
	}
 
	x= new Array(n)
	x[n-1] = r[n-1]/b[n-1];
	for (i = n - 2; i >= 0; --i)
	{	x[i] = (r[i] - c[i] * x[i+1]) / b[i];
	}
	return x;
}

function Thomas4(r,a,b,c,d)
{
	var p,i,n,m
	n = r.length
	p = new Array(n)

	// the following array elements are not in the original matrix, so they should not have an effect
	a[0]=0; // outside the matrix
	c[n-1]=0; // outside the matrix
	d[n-2]=0; // outside the matrix
	d[n-1]=0; // outside the matrix

	/*solves Ax=b with the Thomas algorithm (from Wikipedia)*/
	/* adapted for a 4-diagonal matrix. only the a[i] are under the diagonal, so the Gaussian elimination is very similar */
	for (i = 1; i < n; i++)
	{
		m = a[i]/b[i-1];
		b[i] = b[i] - m * c[i - 1];
		c[i] = c[i] - m * d[i - 1];
		r[i] = r[i] - m * r[i-1];
	}
 
	p[n-1] = r[n-1]/b[n-1];
	p[n-2] = (r[n-2] - c[n-2] * p[n-1]) / b[n-2];
	for (i = n - 3; i >= 0; --i)
	{	p[i] = (r[i] - c[i] * p[i+1]-d[i]*p[i+2]) / b[i];
	}	
/*
	p[n] = 0 // c[n-1] and d[n-2] are outside the matrix
	p[n+1]=0 // d[n-1] is outside the matrix
	for (i = n - 1; i >= 0; --i)
	{	p[i] = (r[i] - c[i] * p[i+1]-d[i]*p[i+2]) / b[i];
	}	
*/
	return p
}