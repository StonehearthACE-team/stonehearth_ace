// credit to StackOverflow user @njlarsson
// https://stackoverflow.com/questions/1590247/how-do-you-implement-a-stack-and-a-queue-in-javascript

const queue = () => {
   const a = [], b = [];
   return {
      push: (...elts) => a.push(...elts),
      shift: () => {
         if (b.length === 0) {
            while (a.length > 1) { b.push(a.pop()) }
            return a.pop();
         }
         return b.pop();
      },
      toArray: () => [...b].reverse().concat(a),
      get length() { return a.length + b.length },
   }
}