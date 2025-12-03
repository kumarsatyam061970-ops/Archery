using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class shoot : MonoBehaviour
{
    public GameObject arrow;
    public Transform parent;
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if(Input.GetKeyDown(KeyCode.Space))
        {
           GameObject obj= Instantiate(arrow,transform.position,transform.rotation);
           obj.transform.parent=parent;
           obj.GetComponent<Rigidbody2D>().AddForce(transform.right*15000);
        }
        
    }
}
