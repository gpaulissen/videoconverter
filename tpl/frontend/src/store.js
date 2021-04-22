import { observable, action, makeObservable } from "mobx";
class ConversionsStore {
    conversions = [];
    
    constructor() {
        makeObservable(this, {
            conversions: observable,
            setConversions: action
        })
    }
    
    setConversions(conversions) {
        this.conversions = conversions;
    }
}
export { ConversionsStore };
